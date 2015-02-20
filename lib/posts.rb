module PostHelper
  # if compiling in production mode, only show published articles
  def blog_articles
    if ENV['NANOC_ENV'] == 'production'
      sorted_articles.select { |a| a[:published] }
    else
      sorted_articles
    end
  end

  def get_post_day(post)
    attribute_to_time(post[:created_at]).strftime('%e')
  end

  def get_post_month(post)
    attribute_to_time(post[:created_at]).strftime('%^b')
  end

  def get_post_start(post)
    content = post.compiled_content
    if content =~ /\s<!-- more -->\s/
      content =
        content.partition('<!-- more -->').first +
        "<div class='read-more'><a href='#{post.path}'>Continue reading &rsaquo;</a></div>"
    end
    content
  end
end

include PostHelper
