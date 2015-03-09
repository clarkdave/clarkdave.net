require 'addressable/template'

activate :blog do |blog|
  blog.permalink = '{year}/{month}/{slug}'
  blog.sources = 'posts/{year}/{year}-{month}-{day}-{title}'
  # blog.source_template = Addressable::Template.new('posts/{year}/{year}-{month}-{day}-{title}')
  # blog.taglink = 'tags/{tag}.html'
  blog.layout = 'post'
  blog.summary_separator = /<!-- more -->/

  # blog.year_link = '{year}.html'
  # blog.month_link = '{year}/{month}.html'
  # blog.day_link = '{year}/{month}/{day}.html'
  blog.default_extension = '.md'

  blog.new_article_template = 'templates/article.tt'
  # blog.tag_template = 'tag.html'
  # blog.calendar_template = 'calendar.html'

  # Enable pagination
  blog.paginate = true
  # blog.per_page = 5
  blog.page_link = 'page/{num}'
end

require 'lib/blog_extensions'

page '/feed.xml', :layout => false

# Automatic image dimensions on image_tag helper
# activate :automatic_image_sizes

activate :livereload
activate :directory_indexes
activate :syntax
activate :autoprefixer

set :css_dir, 'assets/stylesheets'
set :js_dir, 'assets/javascripts'
set :images_dir, 'assets/images'

set :markdown_engine, :redcarpet
set :markdown,
  :fenced_code_blocks => true,
  :smartypants => true,
  :with_toc_data => true

require 'lib/helpers'
helpers NavigationHelpers
helpers SiteHelpers

# Build-specific configuration
configure :build do
  activate :minify_css
  activate :minify_html
  activate :asset_hash
  activate :gzip
  # activate :imageoptim do |options|
  #   options.manifest = true
  #   options.skip_missing_workers = true
  #   options.verbose = false
  #   options.nice = true
  #   options.threads = true
  #   options.image_extensions = %w(.png .jpg .gif .svg)
  # end
end

activate :deploy do |deploy|
  deploy.build_before = true
  deploy.method = :rsync
  deploy.host = 'shell.clarkdave.net'
  deploy.path = '/srv/clarkdave.net'
  deploy.user = 'zoz'
end
