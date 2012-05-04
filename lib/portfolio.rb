
module PortfolioHelper

  def portfolios
    @items.select { |item| item[:kind] == 'portfolio' }
  end

  def sorted_portfolios
    portfolios.sort_by { |p| attribute_to_time(p[:created_at]) }.reverse
  end

end

include PortfolioHelper