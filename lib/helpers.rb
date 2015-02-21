module NavigationHelpers
  def active_page?(page)
    path = current_page.path

    case page
    when 'blog'
      path.start_with?('posts')  || path.start_with?('index') || path.start_with?('page')
    when 'about'
      path.start_with?('about')
    when 'work'
      path.start_with?('work')
    when 'contact'
      path.start_with?('contact')
    end
  end
end

module SiteHelpers
  def posts_count
    page_articles.size
  end

  def words_count
    page_articles.reduce(0) do |memo, article|
      memo + article.body.split(' ').size
    end
  end
end
