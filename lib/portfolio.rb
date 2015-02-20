module PortfolioHelper
  def portfolios
    @items.select { |item| item[:kind] == 'portfolio' }
  end

  def sorted_portfolios
    portfolios.sort_by { |p| attribute_to_time(p[:created_at]) }.reverse
  end

  def portfolio_image_url(item, type)
    '/images/portfolio/' + item[:image_id] + '_' + type + '.jpg'
  end
end

include PortfolioHelper
