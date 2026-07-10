# frozen_string_literal: true

module PSN
  module Resources
    # Cloud media gallery for the AUTHENTICATED account: captured screenshots
    # and video clips. Undocumented mobile-app endpoints
    # (/api/gameMediaService/v2/c2s) that can change without notice; verify
    # changes with bin/smoke.
    #
    # PROVISIONAL (raw bodies, single page): the probe account had zero
    # captures (2026-07-10: {"ugcDocument" => [], "limit" => 0}), so the item
    # shape, the /url response shape and the request-side cursor param for
    # nextCursorMark are all unverified. Model mapping and paging wait until
    # a populated response is seen.
    class Media
      LIST_PATH = "/api/gameMediaService/v2/c2s/category/cloudMediaGallery/ugcType/all"
      URL_PATH = "/api/gameMediaService/v2/c2s/ugc/%s/url"
      PAGE_SIZE = 20

      def initialize(connection)
        @connection = connection
      end

      # PROVISIONAL: raw capture hashes as a lazy enumerator, first page only.
      def captures
        Paginator.cursor do |_cursor|
          response = @connection.get(:mobile, LIST_PATH,
                                     { "limit" => PAGE_SIZE, "includeTokenizedUrls" => "true" })
          [response["ugcDocument"] || [], nil]
        end
      end

      # PROVISIONAL: raw hash of tokenized (expiring) URLs for one capture.
      def download_url(ugc_id)
        @connection.get(:mobile, format(URL_PATH, ugc_id), {})
      end
    end
  end
end
