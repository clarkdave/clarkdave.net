
class SprocketsProcessor
  attr_accessor :environment

  def initialize
    @environment = Sprockets::Environment.new(File.expand_path('.'))

    asset_paths.each do |path|
      @environment.append_path "content/assets/#{path}"
    end
  end

  def asset_paths
    %w(
      stylesheets
      javascripts
      images/icons
      images/layout
      images/portfolio
    )
  end
end

module SprocketsHelper

end

# require 'nanoc-sprockets'

# include Nanoc::Sprockets::Helper

Nanoc::Sprockets::Helper.configure do |config|
  config.environment = ::Sprockets::Environment.new(File.expand_path('.'))

  asset_paths = %w(
    stylesheets
    javascripts
    images/icons
    images/layout
    images/portfolio
  )

  asset_paths.each do |path|
    config.environment.append_path "content/assets/#{path}"
  end

  # config.environment.css_compressor = :scss

  config.prefix      = '/assets'
  config.digest      = true

  # define the asset_path helper which Sprockets uses internally to
  # resolve (for example) `asset-url` calls inside css files
  config.environment.context_class.class_eval do
    def asset_path(path, options = {})
      Nanoc::Sprockets::Helper.asset_path(path, options)
    end
  end
end

# module Nanoc
#   module Sprockets
#     class Filter
#       alias_method :orig_update_dependencies_for_current_item,
#                    :update_dependencies_for_current_item

#       # not sure if due to a bug in `nanoc-sprockets3` or my configuration, but
#       # nil was being passed to this method for assets without dependencies, so
#       # this patch just checks for nil and bails out if need be
#       def update_dependencies_for_current_item(dependencies)
#         return if dependencies.nil?
#         orig_update_dependencies_for_current_item(dependencies)
#       end
#     end
#   end
# end
