require 'net/http'
require 'net/https'
require 'builder'
require 'hpricot'
require 'base64'
require 'json'

require 'active_support/core_ext/hash'

module Net #:nodoc:
  # Helper class for making HTTPS requests
  class HTTPS < HTTP
    def self.start(address, port = nil, p_addr = nil, p_port = nil, p_user = nil, p_pass = nil, &block) #:nodoc:
      https = new(address, port, p_addr, p_port, p_user, p_pass)
      https.use_ssl = true
      https.start(&block)
    end
  end
end

module EFax
  # URL of eFax web service
  Url      = "https://secure.efaxdeveloper.com/EFax_WebFax.serv"
  # URI of eFax web service
  Uri      = URI.parse(Url)
  # Prefered content type
  HEADERS  = {'Content-Type' => 'text/xml'}

  # Base class for OutboundRequest and OutboundStatus classes
  class Request
    @@disposition_level = 'NONE' # Default none

    def self.user
      @@user
    end
    def self.user=(name)
      @@user = name
    end

    def self.password
      @@password
    end
    def self.password=(password)
      @@password = password
    end

    def self.account_id
      @@account_id
    end
    def self.account_id=(id)
      @@account_id = id
    end

    def self.call_back_url = (call_back)
      @@call_back_url =  callback
      @disposition_level = 'POST'
    end

    def self.params(content)
      escaped_xml = ::URI.escape(content, Regexp.new("[^#{::URI::PATTERN::UNRESERVED}]"))
      "id=#{account_id}&xml=#{escaped_xml}&respond=XML"
    end

    private_class_method :params
  end

  class OutboundRequest < Request
    def self.post(name, company, fax_number, subject, content, content_type = :html)
      xml_request = xml(name, company, fax_number, subject, content, content_type)
      response = Net::HTTPS.start(EFax::Uri.host, EFax::Uri.port) do |https|
        https.post(EFax::Uri.path, params(xml_request), EFax::HEADERS)
      end
      OutboundResponse.new(response)
    end

    def self.xml(name, company, fax_number, subject, content, options = {}) #content_type = :html)
      content_type = :pdf

      if (options) 
        content_type = options[:content_type] if options[:content_type]
        transmissionid = options[:transmissionid]
      end
      xml_request = ""
      xml = Builder::XmlMarkup.new(:target => xml_request, :indent => 2 )
      xml.instruct! :xml, :version => '1.0'
      xml.OutboundRequest do
        xml.AccessControl do
          xml.UserName(self.user)
          xml.Password(self.password)
        end
        xml.Transmission do
          xml.TransmissionControl do
            if(transmissionid)
              xml.TransmissionID(transmissionid.to_s)
            end
            xml.Resolution("FINE")
            xml.Priority("NORMAL")
            xml.SelfBusy("ENABLE")
            xml.FaxHeader(subject)
          end
          xml.DispositionControl do
            if @@call_back_url do
              xml.DispositionControl = @@call_back_url
              xml.DispositionLevel = 'BOTH'
              xml.DispositionMethod = 'POST'
            else
              xml.DispositionLevel("NONE")
            end
          end
          xml.Recipients do
            xml.Recipient do
              xml.RecipientName(name)
              xml.RecipientCompany(company)
              xml.RecipientFax(fax_number)
            end
          end
          xml.Files do
            xml.File do
              encoded_content = Base64.encode64(content).delete("\n")
              xml.FileContents(encoded_content)
              xml.FileType(content_type.to_s)
            end
          end
        end
      end
      xml_request
    end

    private_class_method :xml
  end

  class RequestStatus
    HTTP_FAILURE = 0
    SUCCESS      = 1
    FAILURE      = 2
  end
  class OutboundResponse
    attr_reader :status_code
    attr_reader :error_message
    attr_reader :error_level
    attr_reader :doc_id

    def initialize(response)  #:nodoc:
      if response.is_a? Net::HTTPOK
        doc = Hpricot(response.body)
        @status_code = doc.at(:statuscode).inner_text.to_i
        @error_message = doc.at(:errormessage)
        @error_message = @error_message.inner_text if @error_message
        @error_level = doc.at(:errorlevel)
        @error_level = @error_level.inner_text if @error_level
        @doc_id = doc.at(:docid).inner_text
        @doc_id = @doc_id.empty? ? nil : @doc_id
      else
        @status_code = RequestStatus::HTTP_FAILURE
        @error_message = "HTTP request failed (#{response.code})"
      end
    end
  end

  class OutboundStatus < Request
    def self.post(doc_id)
      data = params(xml(doc_id))
      response = Net::HTTPS.start(EFax::Uri.host, EFax::Uri.port) do |https|
        https.post(EFax::Uri.path, data, EFax::HEADERS)
      end
      OutboundStatusResponse.new(response)
    end

    def self.xml(doc_id)
      xml_request = ""
      xml = Builder::XmlMarkup.new(:target => xml_request, :indent => 2 )
      xml.instruct! :xml, :version => '1.0'
      xml.OutboundStatus do
        xml.AccessControl do
          xml.UserName(self.user)
          xml.Password(self.password)
        end
        xml.Transmission do
          xml.TransmissionControl do
            xml.DOCID(doc_id)
          end
        end
      end
      xml_request
    end

    private_class_method :xml
  end

  class QueryStatus
    HTTP_FAILURE = 0
    PENDING      = 3
    SENT         = 4
    FAILURE      = 5
  end

  class OutboundStatusResponse
    attr_reader :status_code
    attr_reader :message
    attr_reader :classification
    attr_reader :outcome

    def initialize(response) #:nodoc:
      f = 'response_body.xml'
      if response.is_a? Net::HTTPOK

        #File.open([Time.now.strftime("%Y-%m-%d-%H%M%S"),f].join("_"), 'w').write response.body
  #      File.open('response_body.xml', 'w') {|f| f.write response.body}
        doc = Hpricot(response.body)
  #     puts doc
        @message = doc.at(:message).innerText
        @classification = doc.at(:classification).innerText.delete('"')
        @outcome = doc.at(:outcome).innerText.delete('"')
        @transmission_id = doc.at(:transmissionid).innerText.delete('"')
        @lastdate = doc.at(:lastdate).innerText.delete('"')
        @lasttime = doc.at(:lasttime).innerText.delete('"')
        @nextdate = doc.at(:nextdate).innerText.delete('"')
        @nexttime = doc.at(:nexttime).innerText.delete('"')
        @remote_csid = doc.at(:remotecsid).innerText.delete('"')
        @pages = doc.at(:sent).innerText.delete('"')

        if(@outcome =~ /probable human/)
          @human = 'PROBABLE HUMAN'
        else
          @human = ''
        end
        # @json = Hash.from_xml(response.body).to_json
        # puts "json = #{@json}"
        if !sent_yet?(classification, outcome) || busy_signal?(classification)
          @status_code = QueryStatus::PENDING
        elsif @classification == "Success" && @outcome == "Success"
          @status_code = QueryStatus::SENT
        else
          @status_code = QueryStatus::FAILURE
        end
      else
        @status_code = QueryStatus::HTTP_FAILURE
        @message = "HTTP request failed (#{response.code})"
      end
    end

    def busy_signal?(classification)
      classification == "Busy"
    end

    def sent_yet?(classification, outcome)
      !classification.empty? || !outcome.empty?
    end

  end
end