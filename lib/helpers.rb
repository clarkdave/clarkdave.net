module NavigationHelpers
  def active_page?(page)
    path = current_page.path

    case page
    when 'blog'
      path.start_with?('posts')  || path.start_with?('index')
    when 'about'
      path.start_with?('about')
    when 'work'
      path.start_with?('work')
    when 'contact'
      path.start_with?('contact')
    end
  end
end
