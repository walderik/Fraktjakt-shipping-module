module Fraktjakt #:nodoc:
  
 
  # The result from a freight-query in Fraktjakt
  #   The result from Fraktjakt are saved as an array of this class
  #   Each object is a description of a shipping_product
  #   id - the id of the shipping_product as integer
  #   desc - The name and description of the product
  #   time - transportation-time (has an alias in arrival_time)
  #   price - price for the transportation. Probably the most important value. Float.
  #   tax_class - Vat if any (0% or 25%). Float.
  #   agent_info - Information about the closest agent, if applicable.
  #   agent_link - A link to find the closest agent.
  #   shipment_id - The shipment_id for the searchResult in Fraktjakt
  class SearchResult
    
    attr_reader :id, :desc, :time, :arrival_time, :price, :tax_class, :agent_info, :agent_link, :agent_in_info, :agent_in_link, :shipment_id
    
    
    # Class method to merge search-results-arrays
    #   Returning only one instance of a shipping_product and then the most expensive one.
    #   Can be called with something like this - results = Fraktjakt::SearchResult.merge_arrays(results1, results2)
    def SearchResult.merge_arrays(results1, results2)
      results = results1 + results2
      return results if results.blank?
      uniq_hash = Hash.new
      results.each { |result| uniq_hash[result.id] = result if uniq_hash[result.id].nil? || (uniq_hash[result.id].price < result.price) }
      new_results = Array.new
      uniq_hash.each { |id,result| new_results << result }
      new_results.sort! do |a,b|
        a_value = (a.price||100000000)
        b_value = (b.price||100000000)
        a_value = 100000000 if a_value == 0
        b_value = 100000000 if b_value == 0
        a_value <=> b_value
      end
      return new_results
    end
    
    def initialize(id, desc, time, price, tax_class, agent_info, agent_link, agent_in_info, agent_in_link, shipment_id) 
      @id = id.to_i
      @desc = desc
      @time = time
      @arrival_time = @time
      @price = price.to_f
      @tax_class = tax_class.to_i
      @agent_info = agent_info
      @agent_link = agent_link
      @agent_in_info = agent_in_info
      @agent_in_link = agent_in_link
      @shipment_id = shipment_id
    end
  end
  
end # Module