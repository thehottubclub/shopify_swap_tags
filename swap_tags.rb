require 'json'
require 'httparty'
require 'pry'
require 'shopify_api'
require 'yaml'

@outcomes = {
  errors: [],
  skipped: [],
  replaced_and_saved_tags: [],
  unable_to_save_tags: [],
  unable_to_replace_tags: [],
  responses: []
}

#Load secrets from yaml & set data values to use
data = YAML::Load( File.open( 'config/secrets.yml' ) )
SECURE_URL_BASE = data['url_base']
API_DOMAIN = data['api_domain']

#Constants
DIVIDER = '------------------------------------------'
DELAY_BETWEEN_REQUESTS = 0.11
NET_INTERFACE = HTTParty
STARTPAGE = 1
ENDPAGE = 75
#Tags to search for and replace
CURRENT_TAG = 'tee' #Tag to find and remove
NEW_TAG = 'tees' #Tag to add

# Need to update to include page range as arguments for do_page_range
# startpage = ARGV[0].to_i
# endpage = ARGV[1].to_i
def main
  puts "starting at #{Time.now}"
  puts "replacing #{CURRENT_TAG} with #{NEW_TAG}"

  if ARGV[0] =~ /product_id=/
    do_product_by_id(ARGV[0].scan(/product_id=(\d+)/).first.first)
  else
    do_page_range
  end

  puts "finished at #{Time.now}"

  File.open(filename, 'w') do |file|
    file.write @outcomes.to_json
  end

  @outcomes.each_pair do |k,v|
    puts "#{k}: #{v.size}"
  end
end

def filename
  "data/find_tag_and_swap_#{Time.now.strftime("%Y-%m-%d_%k%M%S")}.json"
end

def do_page_range
  (STARTPAGE .. ENDPAGE).to_a.each do |current_page|
    do_page(current_page)
  end
end

def do_page(page_number)
  puts "Starting page #{page_number}"

  products = get_products(page_number)

  # counter = 0
  products.each do |product|
    @product_id = product['id']
    do_product(product)
  end

  puts "Finished page #{page_number}"
end

def get_products(page_number)
  response = secure_get("/products.json?page=#{page_number}")

  JSON.parse(response.body)['products']
end

def get_product(id)
  JSON.parse( secure_get("/products/#{id}.json").body )['product']
end

def do_product_by_id(id)
  do_product(get_product(id))
end

def do_product(product)
  begin
    puts DIVIDER
    old_tags = product['tags'].split(', ')

    if( should_skip_based_on?(old_tags) )
      skip(product)
    else
      replace_with_lowercase_tags(product, old_tags)
    end
  rescue Exception => e
    @outcomes[:errors].push @product_id
    puts "error on product #{product['id']}: #{e.message}"
    puts e.backtrace.join("\n")
    raise e
  end
end

#Check if skip method works properly
def should_skip_based_on?(old_tags)
  if old_tags.include?(NEW_TAG)
    return true
  elsif old_tags.exclude?(CURRENT_TAG)
    return true
  end

  false
end

def skip(product)
  @outcomes[:skipped].push @product_id
  puts "Skipping product #{product['id']}"
end

def replace_with_lowercase_tags(product, old_tags)
  if new_tags = replace_tag(old_tags)
    if result = save_tags(product, new_tags)
      @outcomes[:replaced_and_saved_tags].push @product_id
      puts "Saved tags for #{product['id']}: #{new_tags}"
    else
      @outcomes[:unable_to_save_tags].push @product_id
      puts "Unable to save tags for #{product['id']}:  #{result.body}"
    end
  else
    @outcomes[:unable_to_replace_tags].push @product_id
    puts "unable to replace tags_for product #{product['id']}"
  end
end

def replace_tag(old_tags)
  old_tags.delete(CURRENT_TAG)
  old_tags.push(NEW_TAG)
end

def save_tags(product, new_tags)
  secure_put(
    "/products/#{product['id']}.json",
    {product: {id: product['id'], tags: new_tags}}
  )
end


def secure_get(relative_url)
  sleep DELAY_BETWEEN_REQUESTS
  url = SECURE_URL_BASE + relative_url
  result = NET_INTERFACE.get(url)
end

def secure_put(relative_url, params)
  sleep DELAY_BETWEEN_REQUESTS

  url = SECURE_URL_BASE + relative_url

  result = NET_INTERFACE.put(url, body: params)

  @outcomes[:responses].push({
    method: 'put', requested_url: url, body: result.body, code: result.code
  })
end

def put(url, params)
  NET_INTERFACE.put(url, query: params)
end

main
