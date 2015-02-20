module Middleman
  module Blog
    module BlogArticle
      def summary?
        rendered = render layout: false, keep_separator: true

        blog_options.summary_separator &&
          rendered.match(blog_options.summary_separator)
      end
    end
  end
end
