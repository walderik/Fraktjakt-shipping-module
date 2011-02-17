module Fraktjakt #:nodoc:
  
  # The result from a track-query in Fraktjakt
  #   The result from Fraktjakt are saved as an array of this class
  #   shipment_id - Id for the shipment. Might be a different one than the one sent in the call.
  #   Name - Status as text.
  #   Fraktjakt_id - Fraktjakt's internal status as a number
  #   Id - Status as a number 
  #     The meaning of the different numbers:
  #          0 – Handled by the sender
  #          1 – Sent
  #          2 – Delivered
  #          3 – Signed
  #          4 - Returned
  #
  class TrackResult
    attr_reader :shipment_id, :name, :id, :fraktjakt_id
    
    def initialize(shipment_id, name, id, fraktjakt_id)
      @shipment_id = shipment_id.to_i
      @name = name
      @id = id
      @fraktjakt_id = fraktjakt_id
    end
  end
  
end # Module