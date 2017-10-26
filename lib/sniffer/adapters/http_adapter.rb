# frozen_string_literal: true

module Sniffer
  module Adapters
    # HTTP adapter
    module HTTPAdapter
      def self.included(base)
        base.class_eval do
          alias_method :request_without_sniffer, :request
          alias_method :request, :request_with_sniffer
        end
      end

      # private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def request_with_sniffer(verb, uri, opts = {})
        opts    = @default_options.merge(opts)
        uri     = make_request_uri(uri, opts)
        headers = make_request_headers(opts)
        body    = make_request_body(opts, headers)
        proxy   = opts.proxy

        req = HTTP::Request.new(
          verb: verb,
          uri: uri,
          headers: headers,
          proxy: proxy,
          body: body,
          auto_deflate: opts.feature(:auto_deflate)
        )

        if Sniffer.enabled?
          data_item = Sniffer::DataItem.new
          data_item.request = Sniffer::DataItem::Request.new.tap do |r|
            query = uri.path
            query += "?#{uri.query}" if uri.query
            r.host = uri.host
            r.method = verb
            r.query = query
            r.headers = headers.collect.to_h
            r.body = body.to_s
            r.port = uri.port
          end

          Sniffer.store(data_item)
        end

        bm = Benchmark.realtime do
          @res = perform(req, opts)
        end

        if Sniffer.enabled?
          data_item.response = Sniffer::DataItem::Response.new.tap do |r|
            r.status = @res.code
            r.headers = @res.headers.collect.to_h
            r.body = @res.body.to_s
            r.benchmark = bm
          end

          data_item.log
        end

        return @res unless opts.follow

        HTTP::Redirector.new(opts.follow).perform(req, @res) do |request|
          perform(request, opts)
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    end
  end
end

HTTP::Client.send(:include, Sniffer::Adapters::HTTPAdapter) if defined?(::HTTP::Client)