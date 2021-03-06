require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/hash/slice'

module ActionDispatch
  module Http
    module URL
      IP_HOST_REGEXP = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/

      mattr_accessor :tld_length
      self.tld_length = 1

      class << self
        def extract_domain(host, tld_length = @@tld_length)
          host.split('.').last(1 + tld_length).join('.') if named_host?(host)
        end

        def extract_subdomains(host, tld_length = @@tld_length)
          if named_host?(host)
            parts = host.split('.')
            parts[0..-(tld_length + 2)]
          else
            []
          end
        end

        def extract_subdomain(host, tld_length = @@tld_length)
          extract_subdomains(host, tld_length).join('.')
        end

        def url_for(options = {})
          path  = options.delete(:script_name).to_s.chomp("/")
          path << options.delete(:path).to_s

          params = options[:params].is_a?(Hash) ? options[:params] : options.slice(:params)
          params.reject! { |_,v| v.to_param.nil? }

          result = build_host_url(options)
          if options[:trailing_slash]
            if path.include?('?')
              result << path.sub(/\?/, '/\&')
            else
              result << path.sub(/[^\/]\z|\A\z/, '\&/')
            end
          else
            result << path
          end
          result << "?#{params.to_query}" unless params.empty?
          result << "##{Journey::Router::Utils.escape_fragment(options[:anchor].to_param.to_s)}" if options[:anchor]
          result
        end

        private

        def build_host_url(options)
          if options[:host].blank? && options[:only_path].blank?
            raise ArgumentError, 'Missing host to link to! Please provide the :host parameter, set default_url_options[:host], or set :only_path to true'
          end

          result = ""

          unless options[:only_path]
            protocol = extract_protocol(options)
            unless options[:protocol] == false
              result << protocol
              result << ":" unless result.match(%r{:|//})
            end
            result << "//" unless result.match("//")
            result << rewrite_authentication(options)
            result << host_or_subdomain_and_domain(options)
            result << ":#{options.delete(:port)}" if options[:port]
          end
          result
        end

        def named_host?(host)
          host && IP_HOST_REGEXP !~ host
        end

        def rewrite_authentication(options)
          if options[:user] && options[:password]
            "#{Rack::Utils.escape(options[:user])}:#{Rack::Utils.escape(options[:password])}@"
          else
            ""
          end
        end

        # Extracts protocol http:// or https:// from options[:host]
        # needs to be called whether the :protocol is being used or not
        def extract_protocol(options)
          if options[:host] && match = options[:host].match(/(^.*:\/\/)(.*)/)
            options[:protocol] ||= match[1]
            options[:host]     =   match[2]
          end
          options[:protocol] || "http"
        end

        def host_or_subdomain_and_domain(options)
          return options[:host] if !named_host?(options[:host]) || (options[:subdomain].nil? && options[:domain].nil?)

          tld_length = options[:tld_length] || @@tld_length

          host = ""
          unless options[:subdomain] == false
            host << (options[:subdomain] || extract_subdomain(options[:host], tld_length)).to_param
            host << "."
          end
          host << (options[:domain] || extract_domain(options[:host], tld_length))
          host
        end
      end

      def initialize(env)
        super
        @protocol = nil
        @port     = nil
      end

      # Returns the complete URL used for this request.
      def url
        protocol + host_with_port + fullpath
      end

      # Returns 'https://' if this is an SSL request and 'http://' otherwise.
      def protocol
        @protocol ||= ssl? ? 'https://' : 'http://'
      end

      # Returns the \host for this request, such as "example.com".
      def raw_host_with_port
        if forwarded = env["HTTP_X_FORWARDED_HOST"]
          forwarded.split(/,\s?/).last
        else
          env['HTTP_HOST'] || "#{env['SERVER_NAME'] || env['SERVER_ADDR']}:#{env['SERVER_PORT']}"
        end
      end

      # Returns the host for this request, such as example.com.
      def host
        raw_host_with_port.sub(/:\d+$/, '')
      end

      # Returns a \host:\port string for this request, such as "example.com" or
      # "example.com:8080".
      def host_with_port
        "#{host}#{port_string}"
      end

      # Returns the port number of this request as an integer.
      def port
        @port ||= begin
          if raw_host_with_port =~ /:(\d+)$/
            $1.to_i
          else
            standard_port
          end
        end
      end

      # Returns the standard \port number for this request's protocol.
      def standard_port
        case protocol
          when 'https://' then 443
          else 80
        end
      end

      # Returns whether this request is using the standard port
      def standard_port?
        port == standard_port
      end

      # Returns a number \port suffix like 8080 if the \port number of this request
      # is not the default HTTP \port 80 or HTTPS \port 443.
      def optional_port
        standard_port? ? nil : port
      end

      # Returns a string \port suffix, including colon, like ":8080" if the \port
      # number of this request is not the default HTTP \port 80 or HTTPS \port 443.
      def port_string
        standard_port? ? '' : ":#{port}"
      end

      def server_port
        @env['SERVER_PORT'].to_i
      end

      # Returns the \domain part of a \host, such as "rubyonrails.org" in "www.rubyonrails.org". You can specify
      # a different <tt>tld_length</tt>, such as 2 to catch rubyonrails.co.uk in "www.rubyonrails.co.uk".
      def domain(tld_length = @@tld_length)
        ActionDispatch::Http::URL.extract_domain(host, tld_length)
      end

      # Returns all the \subdomains as an array, so <tt>["dev", "www"]</tt> would be
      # returned for "dev.www.rubyonrails.org". You can specify a different <tt>tld_length</tt>,
      # such as 2 to catch <tt>["www"]</tt> instead of <tt>["www", "rubyonrails"]</tt>
      # in "www.rubyonrails.co.uk".
      def subdomains(tld_length = @@tld_length)
        ActionDispatch::Http::URL.extract_subdomains(host, tld_length)
      end

      # Returns all the \subdomains as a string, so <tt>"dev.www"</tt> would be
      # returned for "dev.www.rubyonrails.org". You can specify a different <tt>tld_length</tt>,
      # such as 2 to catch <tt>"www"</tt> instead of <tt>"www.rubyonrails"</tt>
      # in "www.rubyonrails.co.uk".
      def subdomain(tld_length = @@tld_length)
        ActionDispatch::Http::URL.extract_subdomain(host, tld_length)
      end
    end
  end
end
