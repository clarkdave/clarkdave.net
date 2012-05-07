include Nanoc3::Helpers::Blogging
include Nanoc3::Helpers::Tagging
include Nanoc3::Helpers::Rendering
include Nanoc3::Helpers::LinkTo

module NavHelper

	def nav_link(name, path, current)
		ident = item.identifier

		# nav rules
		if (path == '/' and (ident.start_with? '/posts' or ident == '/')) or
				(path == '/work' and (ident.start_with? '/portfolio' or ident.start_with? '/work')) or
				(path == '/about' and ident.start_with? '/about') or
				(path == '/contact' and ident.start_with? '/contact')
			clazz = " class='active'" 
		else
			clazz = ''
		end

		"<a#{clazz} href='#{path}'>#{name}</a>"
	end
end
include NavHelper

module PostHelper

	def blog_articles
		sorted_articles.select{|a| a[:published] }
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
			content = content.partition('<!-- more -->').first +
			"<div class='read-more'><a href='#{post.path}'>Continue reading &rsaquo;</a></div>"
		end
		return content
	end
end
include PostHelper