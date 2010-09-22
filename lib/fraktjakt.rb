module Fraktjakt #:nodoc:
  
  class MissingInformationError < StandardError; end #:nodoc:
  class FraktjaktError < StandardError; end #:nodoc
  
  # Provides access to Fraktjakt Services
  class Fraktjakt
    
    # Defines the required parameters for various methods
    REQUIRED_OPTIONS = {
      :base           => [ :consignor_id, :consignor_key ], 
      :order          => [ :shipping_product_id, :recipient ],
      :address        => [ :street1, :city_name ],
      :parcel         => [ :weight, :length, :height, :width ],
      :commodity      => [ :name, :quantity ]
    }
    
    attr_accessor :consignor_id, :consignor_key, :currency, :language,
                  :commodities, :parcels, :shipment_id,
                  :debug
    
    
    # To create a Fraktjakt object, send in the following options:
    #   :consignor_id - are found in the webshops profile page in Fraktjakt - Prod = http://api1.fraktjakt.se/webshops/install
    #   :consignor_key - are found on the same page
    #   :currency - not in use by Fraktjakt right now
    #   :language - not in use by Fraktjakt right now
    #   :debug - If you want to call the test-server (api2.fraktjakt.se) or the production-server (api1.fraktjakt.se). Also the amount of logging done.
    #            Please note that you will need different :consignor_id and :consignor_key in test and production! 
    def initialize(options = {})
      check_required_options(:base, options)
      @consignor_id = options[:consignor_id]
      @consignor_key = options[:consignor_key]
      @currency = options[:currency] || 'SEK'
      @language = options[:language] || 'sv'  # in ISO 639-1 notation
      @debug = options[:debug]
      RAILS_DEFAULT_LOGGER.debug "--> Fraktjakt options #{options.inspect}" if @debug
    end
    
    
    
    # The Method to find the best shipment from Fraktjakt
    #
    #     To do a freight query follow these steps:
    #
    #    1. Create a Fraktjakt-object
    #          fraktjakt = Fraktjakt::Fraktjakt.new( :consignor_id => 2, :consignor_key => '04c959d8259e811342e01d5025bb35e460eb105e', :debug => true )
    #
    #    2. Add parcels 
    #          fraktjakt.add_parcel( :weight => 1, :length => 15, :width => 7, :height => 3 )
    #
    #    3. Create an address-hash for the receiver
    #       address = {   :street1 => 'c/o Johansson',       # Mandatory
    #                     :street2 => 'Östra storgatan 49',  # optional
    #                     :postal_code => '55321',           # Not needed in countries that don't use postal codes such as Gabon.
    #                     :city_name => 'Jönköping',         # Optional of in Sweden and :postal_code is provided.
    #                     :country_subdivision_code => 'F',  # Only needed in USA, Canada and their territorys, such as Puerty Rico.
    #                     :country_code => 'SE',             # According to ISO 3166-1 alpha-2 -  Optional if Sweden
    #                     :residential => true               # If it is a residential-address or a company-address
    #                  }
    #    
    #    3. Do a search-call. Available options are listed below.
    #          begin
    #            @shipment_id, @warning, @res = fraktjakt.shipment(:express => false, :value => 4, :address => address)
    #          rescue Fraktjakt::FraktjaktError
    #            @error_message = $!
    #          end
    #
    #    4. The result comes as a shipment_id (used in the order-call), warning-messages (if any) and an array of SearchResult-objects (if any result are found)
    #
    #    5. Present the search-result in your application:
    #       <% if @error_message.blank? %>
    #        <h1>Results</h1>
    #        <b>Shipment_id: <%= @shipment_id %></b><br />
    #        <b>Warnings: <%= @warnings %></b><br />
    #        <br />
    #        <% @res.each do |res| %>
    #          <%= res.id %> - <%= res.desc %> : <%= res.price %>
    #          <%= link_to 'Select', {:action => 'order', :id => res.id, :shipment_id => @shipment_id} %>
    #          <br />
    #        <%end%>
    #      <%else%>
    #       <h1> No search result due to:<br />
    #        <%= @error_message %></h1>
    #      <%end%>
    #    
    #   From the result you link to the order-action that will create an order in Fraktjakt.
    #
    # 
    #   Available optional options are:
    #     Boolean
    #       Express   : If true, only express-products will be returned. If false, all products will be returned.
    #       Pickup    : If true, only products including pickup will be returned. If false, all products will be returned.
    #       dropoff   : If true, only products including dropoff will be returned. If false, all products will be returned.
    #       green     : If true, only green.marked products are returned. If false, all products will be returned.
    #       quality   : If true, only quality-marked products are returned. If false, all products will be returned.
    #       time_guarantie : If true, only products including time_guarantie will be returned. If false, all products will be returned.
    #       cold      : If true, only products spially handling cold products will be returned. If false, no such products will be returned.
    #       frozen    : If true, only products spially handling frozen products will be returned. If false, no such products will be returned.
    #       no_agents : If true, no information about closest agents and no links to them will be returned. This is a faster query. If false, all agent info will be returned.
    #       no_price  : If true, no price-information in the result will be returned. This is a faster query. If false, all price-info will be returned.
    #     
    #     Integer
    #       shipping_product_id : If provided, the shipment-method will only search for this product. A whole list of avalible ID can be found at:
    #                             http://www.fraktjakt.se/shipping_products/xml_list
    #
    #     Float
    #       value     : The cummulative value of all items in the shipment.
    def shipment(options = {})
      options[:value] = '1.0' if options[:value].blank? || options[:value].to_f < 1
      RAILS_DEFAULT_LOGGER.debug "--> parcels = #{@parcels}" if @debug
      xml = xml_header('shipment')
      xml += xml_shipment_options(options)
      xml += xml_parcels
      xml += xml_address('address_from', set_address(options[:address_from])) unless options[:address_from].nil?
      xml += xml_address('address_to', set_address(options[:address])) unless options[:address].nil?
      xml += '</shipment>'
      RAILS_DEFAULT_LOGGER.debug "--> xml = #{xml.inspect}" if @debug
      xml = CGI.escape(xml||"") #.gsub(/\+/,' ')
      if @debug
        url = URI.parse('http://192.168.66.18:3011/fraktjakt/query_xml?xml='+xml)
      else
        url = URI.parse('http://192.168.66.19:3011/fraktjakt/query_xml?xml='+xml)
      end  
      search_results = Array.new
      res = Net::HTTP.get_response url
      RAILS_DEFAULT_LOGGER.debug "--> res = " + res.inspect if @debug
      case res
      when Net::HTTPSuccess, Net::HTTPRedirection
        body = res.body
        root = get_element(REXML::Document.new(body), "Anropet är inte en korrekt XML.")
        shipment = get_element(root.elements['shipment'], "Priserna från Fraktjakt kan för närvarande inte hämtas.")
        code, dummy = get_text(shipment.elements['code'], "Priserna kan inte hämtas.")
        if code.to_i == 2
          error_message, dummy = get_text(shipment.elements['error_message'], "Priserna kan inte hämtas.")
          raise FraktjaktError.new(error_message)
        elsif code.to_i == 1
          warning_message = get_text(shipment.elements['warning_message'], "Priserna kan hämtas.", false)
        end
        shipment_id, dummy = get_text(shipment.elements['id'], "Sändningen saknar id.")
        prods = get_element(shipment.elements['shipping_products'], "Inga frakttjänster funna som matchar ett sådant paket.")
        prods.elements.each do |prod|
          id, dummy   = get_text(prod.elements['id'], "ID saknas för resultatet.")
          desc, dummy = get_text(prod.elements['description'], "Namn saknas för resultatet.")
          time, dummy = get_text(prod.elements['arrival_time'], "Ankomsttid saknas för resultatet.", false)
          price, dummy = get_text(prod.elements['price'], "Priset saknas för resultatet.")
          tax_class, dummy = get_text(prod.elements['tax_class'], "Momsangivelse saknas för resultatet.")
          agent_info, dummy = get_text(prod.elements['agent_info'], "Ombudsinfo saknas för resultatet.", false)
          agent_link, dummy = get_text(prod.elements['agent_link'], "Ombudslänken saknas för resultatet.", false)
          search_results << SearchResult.new(id, desc, time, price, tax_class, agent_info, agent_link)
        end
      else
        raise FraktjaktError.new("Vi har för närvarande ingen kontakt med Fraktjakt.")
      end
      return shipment_id, warning_message, search_results
    end
    
    
    # The method to create an order in Fraktjakt.
    #
    #     To create a freight order follow these steps:
    #
    #    1. Create a Fraktjakt-object
    #          fraktjakt = Fraktjakt::Fraktjakt.new( :consignor_id => 2, :consignor_key => '04c959d8259e811342e01d5025bb35e460eb105e', :debug => true )
    #    
    #    2. catch the selected shipping_product
    #          shipping_product_id = params[:id]
    #
    #    3. Create a recipient-Hash
    #          recipient = { :name_to => 'Lina Sandell',      # You have to provide :name_to or :company_to
    #                        :company_to => 'Kottegott',   
    #                        :telephone_to => '0733-710252',  # You should provide as much info how to contact the recipient as possible.
    #                        :mobile_to =>  '0733-710252',    # :telephone_to is the most important info, but _email_to is also very inportant.
    #                        :email_to => 'mats@sverok.se'    # At least one method is required.
    #                      }
    #
    #    4. Add the commodities (varuslagen)
    #         fraktjakt.add_commodity(:name => 'Yllesocka', :quantity=>2)  # See add_commodity for alla available and needed options.
    #
    #    5. You may now create a bokking_hash. This is optional and if booking is needed, but not prrovided, the settings for the webshop will be used.
    #       this is the recomended way to handle bookings.
    #         booking = {  :driving_instruction => 'Hit och dit', # Optional
    #                      :user_notes => 'You must call me at 0733-710252',  # Optional 
    #                      :pickup_date => '2010-10-07', # Optional : This must be a working-date in the future and in the format (YYYY-MM-DD)
    #                      :ready_time => '07:00',       # Optional : This time should be as early as possible, and it must be in the future and be of the format (HH:MM)
    #                      :close_time => '18:00'        # Optional : his time should be as late in the afternoon as possible, and it must be in the future and be of the format (HH:MM)
    #                   }
    #   
    #    5. Create the order.
    #        begin
    #          @shipment_id, @warning, @order_id = fraktjakt.order(:value => 4, :shipping_product_id=> shipping_product_id, :recipient => recipient, :shipment_id => @shipment_id)
    #        rescue Fraktjakt::FraktjaktError
    #          @error_message = $!
    #        end
    #
    #        The result is easy to handle and you just have to present the new order_id
    #    
    #    Note that you can reuse a shipment_id several times from a freight-query. 
    #    If you reuse an old shipment_id, a new one will be returned to you.
    #
    #   Available required options are:
    #     Integer
    #       shipment_id  : This must be an ID that you have received in a response from the Query API. 
    #                      If you have already used the same shipment ID in a previous call to the Order API, 
    #                      Fraktjakt will create a new copy of the existing shipment record with a new shipment ID (but with the same shipment details).
    #       shipping_product_id : The shipping product's ID in Fraktjakt. This must be an ID that you have received in a response from the Query API.
    #
    #   In addition you also has to have at least one commcodity added with add_commodity
    #   and a recipient-hash as in the example
    #
    # 
    #   Available optional options are:
    #     String
    #       reference    : Free text that refers to the order in Fraktjakt. 
    #                      This element may contain your own system's order ID, an identifying text, or some other. 
    #                      This text will appear on your shipping labels.
    #       sender_email : Only applies to pre-paid shipping : The e-mail address of the person who will be 
    #                      handling the shipment, if not the consignor. 
    #   In additions you can also provide booking information as in the example above. this is not hte recomended way to make a booking and are totaly optional.
    #        
    def order(options = {})
      check_required_options(:order, options)
      if options[:recipient][:name_to].blank? && options[:recipient][:company_to].blank?
        raise MissingInformationError.new("You have not entered :name_to or _company_to for recipient")
      end
      if options[:recipient][:telephone_to].blank? && options[:recipient][:mobile_to].blank? && options[:recipient][:email_to].blank?
        raise MissingInformationError.new("You have not entered a contact method to the recipient. Add at least telephone.")
      end
      options[:value] = '1.0' if options[:value].blank? || options[:value].to_f < 1
      xml = xml_header('order')
      xml += xml_order_options(options)
      xml += xml_recipient(options[:recipient])
      xml += xml_commodities
      xml += xml_booking(options[:booking]) unless options[:booking].blank?
      xml += '</order>'
      RAILS_DEFAULT_LOGGER.debug "--> xml = #{xml.inspect}" if @debug
      xml = CGI.escape(xml||"") 
      if @debug
        url = URI.parse('http://192.168.66.18:3011/orders/order_xml?xml='+xml)
      else
        url = URI.parse('http://192.168.66.19:3011/orders/order_xml?xml='+xml)
      end

      search_results = Array.new
      res = Net::HTTP.get_response url
      RAILS_DEFAULT_LOGGER.debug "--> res = " + res.inspect if @debug
      case res
      when Net::HTTPSuccess, Net::HTTPRedirection
        body = res.body
        root = get_element(REXML::Document.new(body), "Anropet är inte en korrekt XML.")
        result = get_element(root.elements['result'], "Fraktjakt kan inte skapa en order.")
        code, dummy = get_text(result.elements['code'], "Priserna kan inte hämtas.")
        if code.to_i == 2
          error_message, dummy = get_text(result.elements['error_message'], "Priserna kan inte hämtas.")
          raise FraktjaktError.new(error_message)
        elsif code.to_i == 1
          warning_message = get_text(result.elements['warning_message'], "Priserna kan hämtas.", false)
        end
        shipment_id = get_element(result.elements['shipment_id'], "Fraktjakt kan för närvarande inte hämta aktuell shipment.")
        order_id = get_element(result.elements['order_id'], "Ingen order skapad i Fraktjakt.")
      else
        raise FraktjaktError.new("Vi har för närvarande ingen kontakt med Fraktjakt.")
      end
      return shipment_id, warning_message, order_id
    end
    
    
    # Method to add a parcel to a shipment. You have to do that before a freight-search.
    # To add parcels 
    #   fraktjakt.add_parcel( :weight => 1, :length => 15, :width => 7, :height => 3 )   
    def add_parcel(parcel)
      check_required_options(:parcel, parcel)
      parcel[:length] = 1 if (parcel[:length].nil? || parcel[:length].to_f < 1) 
      parcel[:width]  = 1 if (parcel[:width].nil?  || parcel[:width].to_f  < 1) 
      parcel[:height] = 1 if (parcel[:height].nil? || parcel[:height].to_f < 1) 
      @parcels ||= Array.new
      @parcels << parcel
    end
 
 
    # Method to add the commodities to an order. You need to do that before you create an order in Fraktjakt.
    # To add a commodity
    #   fraktjakt.add_commodity(:name => 'Yllesocka', :quantity=>2)
    #   :name needs to be in a language understood in the receiver's country.
    #
    # Other options:
    #   quantity_units : In what unit are the commodity measused.
    #                  Allowed values are:
    #                        EA = styck
    #                        DZ = dussin
    #                        L = liter
    #                        ML = mililiter
    #                        KG = kilogram
    #                        Default är EA (each) om inget värde anges.
    #   taric : International standard-Code for each type of commodity. https://tid.tullverket.se/taric/TAG_Search.aspx
    #           Always optional, but when you include this element in international shipping orders, the shipments will 
    #           normally get through customs much faster.
    #
    #   The following options are needed for international shipments: 
    #   unit_price    : How much is each unit of the unit_type worth. 
    #   description   : Should be in a language understood in the receiver's country.
    #   country_of_manufacture : Where the commodity are manufacture.
    #   weight        : The total weight of all commodities must be the sama as the total weight for alla parcels.
    # 
    def add_commodity(commodity)
      check_required_options(:commodity, commodity)
      unless commodity[:quantity_units].blank? || !['EA','DZ','L','ML','KG'].include?(commodity[:quantity_units])
        raise MissingInformationError.new("Wrong type of quantity_units")
      end
      @commodities ||= Array.new
      @commodities << commodity
    end
    
    
    
    
    
    private
    
    def check_required_options(option_set_name, options = {}) #:nodoc:
      # Method checking the bare minimum of information
      required_options = REQUIRED_OPTIONS[option_set_name]
      missing = []
      required_options.each{|option| missing << option if options[option].nil?}      
      unless missing.empty?
        string=missing.collect{|m| ":#{m}"}.join(', ')
        raise MissingInformationError.new("You have not entered #{string}")
      end
    end
    
    def set_address(address) #:nodoc:
      # Setting a address with needed data
      check_required_options(:address, address)
      address[:residential] = true if address[:residential].nil?
      address[:country_code] = 'SE' if address[:country_code].nil?
      return address
    end
    
    def xml_header(type) #:nodoc:
      # Standard first tags in the XMl to Fraktjakt
      res  = '<?xml version=\\"1.0\\" encoding=\\"iso-8859-1\\"?>'
      res += "<#{type.to_s}>" 
      res += "<consignor><id>#{@consignor_id}</id><key>#{@consignor_key}</key>"
      res += "<currency>#{@currency||'SEK'}</currency><language>#{@language||'sv'}</language></consignor>"
			return res
    end
    
    def xml_shipment_options(options) #:nodoc:
      res  = build_option_tag(:boolean, ['express', 'pickup', 'dropoff', 'green', 'quality', 'time_guarantie', 'cold', 'frozen', 'no_agents', 'no_price'], options)
      res += build_option_tag(:integer, ['shipping_product_id'], options)
      res += build_option_tag(:float, ['value'], options)
      return res
    end
    
    def xml_order_options(options) #:nodoc:
      res += build_option_tag(:integer, ['shipment_id', 'shipping_product_id'], options)
      res += build_option_tag(:float, ['value'], options)
      res += build_option_tag(:string, ['sender_email'], options)
      return res
    end
    
    def build_option_tag(option_type, available_options, options_in) #:nodoc:
      res = ''
      available_options.each do |option|
        RAILS_DEFAULT_LOGGER.debug "--> options[#{option.to_sym}] = #{options_in[option.to_sym]}" if @debug
        tag_value = case option_type
          when :boolean then options_in[option.to_sym]
          when :integer then options_in[option.to_sym].to_i
          when :float   then options_in[option.to_sym].to_f
          when :string  then options_in[option.to_sym]
        end
        if option_type == :boolean
          res += "<#{option}>#{tag_value}</#{option}>" unless tag_value.nil? || !(tag_value==true || tag_value==false)         
        else
          res += "<#{option}>#{tag_value}</#{option}>" unless tag_value.blank? || tag_value==0
        end
      end
      return res
    end
    
    def xml_parcels #:nodoc:
      raise MissingInformationError.new("You need to add at least one parcel with Fraktjakt#add_parcel.") if @parcels.blank?
      res = '<parcels>'
      @parcels.each do |parcel|
        res += "<parcel><weight>#{(parcel[:weight]||1)}</weight>"
        res += "<length>#{(parcel[:length]||1)}</length>"
        res += "<width>#{(parcel[:length]||1)}</width>"
        res += "<height>#{(parcel[:height]||1)}</height>"
        res += "</parcel>"
      end
      return res+'</parcels>'
    end
    
    def xml_commodities #:nodoc:
      raise MissingInformationError.new("You need to add at least one commodity with Fraktjakt#add_commodity.") if @commodities.blank?
      res = '<commodities>'
      @commodities.each do |commodity|
        res += "<commodity><name>#{commodity[:name]}</name>"
        res += "<quantity>#{(commodity[:quantity]||1)}</quantity>"
        res += "<taric>#{commodity[:taric]}</taric>" unless commodity[:taric].blank?
        res += "<quantity_units>#{(commodity[:quantity_units]||'EA')}</quantity_units>" 
        res += "<description>#{commodity[:description]}</description>" unless commodity[:description].blank?
        res += "<country_of_manufacture>#{(commodity[:country_of_manufacture]||'SE')}</country_of_manufacture>"
        res += "<weight>#{commodity[:weight]}</weight>" unless commodity[:weight].blank?
        res += "<unit_price>#{commodity[:unit_price]}</unit_price>" unless commodity[:unit_price].blank?
        res += "</commodity>"
      end
      return res+'</commodities>'
    end
    
    def xml_address(type, address) #:nodoc:
      res = '<' + type +'>'
      unless address.nil?
        res += "<street_address_1>#{address[:street1]}</street_address_1>"
        res += "<street_address_2>#{address[:street2]}</street_address_2>" unless address[:street2].blank?
        res += "<postal_code>#{address[:postal_code]}</postal_code>" unless address[:postal_code].blank?
        res += "<city_name>#{address[:city_name]}</city_name>" 
        res += "<country_code>#{(address[:country_code]||'SE')}</country_code>"
        res += "<country_subdivision_code>#{address[:country_subdivision_code]}</country_subdivision_code>" unless address[:country_subdivision_code].blank?
        res += "<residential>#{(address[:residential]==true).to_s}</residential>"
      end
      return res + '</' + type +'>'
    end
    
    def xml_recipient(recipient) #:nodoc:
      res  = '<recipient>'
      res += build_option_tag(:string, ['company_to', 'name_to', 'telephone_to', 'mobile_to', 'email_to'], recipient)
      return res + '</recipient>'
    end
    
    def xml_booking(booking)
      res  = '<booking>'
      res += build_option_tag(:string, ['driving_instruction', 'user_notes', 'pickup_date', 'ready_time', 'close_time'], booking)
      return res + '</booking>'
    end
    
    def get_element(element, error_text, mandatory=true) #:nodoc:
      the_element = element
      raise FraktjaktError.new(error_text) if the_element.nil? && mandatory
      return the_element
    end
    
    def get_text(element, error_text, mandatory=true) #:nodoc:
      notice = ""
      the_element = get_element(element,error_text,mandatory) 
      if the_element.nil?
        raise FraktjaktError.new(error_text) if mandatory
        return nil, error_text
      end
      text = the_element.text
      raise FraktjaktError.new(error_text+" Textvärdet saknas.") if text.nil? && mandatory
      notice = error_text if text.nil?
      text = text.first if text.class=='Array'
      return text, notice
    end    
    
  end # Base
  
  
  
  
  # The result from a freight-query in Fraktjakt
  #   The result from Fraktjakt are saved as an array of this class
  #   Each object is a description of a shipping_product
  #   id - the id of the shipping_product
  #   desc - The name and description of the product
  #   time - transportation-time
  #   price - price for the transportation. Probably the most important value.
  #   tax_class - Vat if any (0% or 25%).
  #   agent_info - Information about the closest agent, if applicable.
  #   agent_link - A link to find the closest agent.
  class SearchResult
    attr_reader :id, :desc, :time, :price, :tax_class, :agent_info, :agent_link
    
    def initialize(id, desc, time, price, tax_class, agent_info, agent_link) #:nodoc:
      @id = id
      @desc = desc
      @time = time
      @price = price
      @tax_class = tax_class
      @agent_info = agent_info
      @agent_link = agent_link
    end
    
  end
  
end # Module