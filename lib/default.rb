include Nanoc3::Helpers::Blogging
include Nanoc3::Helpers::Tagging
include Nanoc3::Helpers::Rendering
include Nanoc3::Helpers::LinkTo

module TimestampHelper
  def timestamp
    Time.now.to_i
  end
end

include TimestampHelper
