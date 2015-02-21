###
# Blog settings
###

# Time.zone = 'UTC'

activate :blog do |blog|
  # This will add a prefix to all links, template references and source paths
  # blog.prefix = 'blog'

  blog.permalink = '{year}/{month}/{slug}'
  blog.sources = 'posts/{year}/{title}'
  # blog.taglink = 'tags/{tag}.html'
  blog.layout = 'post'
  blog.summary_separator = '<!-- more -->'

  # blog.year_link = '{year}.html'
  # blog.month_link = '{year}/{month}.html'
  # blog.day_link = '{year}/{month}/{day}.html'
  blog.default_extension = '.md'

  blog.tag_template = 'tag.html'
  # blog.calendar_template = 'calendar.html'

  # Enable pagination
  blog.paginate = true
  # blog.per_page = 5
  blog.page_link = 'page/{num}'
end

require 'lib/blog_extensions'

page '/feed.xml', :layout => false

###
# Compass
###

# Change Compass configuration
# compass_config do |config|
#   config.output_style = :compact
# end

###
# Page options, layouts, aliases and proxies
###

# Per-page layout changes:
#
# With no layout
# page '/path/to/file.html', layout: false
#
# With alternative layout
# page '/path/to/file.html', layout: :otherlayout
#
# A path which all have the same layout
# with_layout :admin do
#   page '/admin/*'
# end

# Proxy pages (http://middlemanapp.com/basics/dynamic-pages/)
# proxy '/this-page-has-no-template.html', '/template-file.html', locals: {
#  which_fake_page: 'Rendering a fake page with a local variable' }

###
# Helpers
###

# Automatic image dimensions on image_tag helper
# activate :automatic_image_sizes

activate :livereload
activate :directory_indexes
activate :syntax

set :css_dir, 'stylesheets'
set :js_dir, 'javascripts'
set :images_dir, 'images'

set :markdown_engine, :redcarpet
set :markdown,
  :fenced_code_blocks => true,
  :smartypants => true,
  :with_toc_data => true

require 'lib/helpers'
helpers NavigationHelpers

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
