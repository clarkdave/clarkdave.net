module NavHelper
  def nav_link(name, path, _current)
    ident = item.identifier

    active =
      case path
      when '/'
        ident.start_with?('/posts') || ident == '/'
      when '/work'
        ident.start_with?('/portfolio') || ident.start_with?('/work')
      when '/about'
        ident.start_with?('/about')
      when '/contact'
        ident.start_with?('/contact')
      end

    clazz = active ? " class='active'" : ''

    "<a#{clazz} href='#{path}'>#{name}</a>"
  end
end

include NavHelper
