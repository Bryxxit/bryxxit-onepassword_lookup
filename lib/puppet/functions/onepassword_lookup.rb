require 'uri'
require 'net/http'
require 'json'
# The `onepassword_lookup` is a hiera 5 `lookup_key` data provider function.
Puppet::Functions.create_function(:onepassword_lookup) do

  dispatch :onepassword_lookup do
    param 'String[1]', :key
    param 'Hash[String[1],Any]', :options
    param 'Puppet::LookupContext', :context
  end

  def onepassword_lookup(key, options, context)
    return context.cached_value(key) if context.cache_has_key(key)
    # if opurls_only is set to true, then we will only look for keys that start with op://, and if the key does not start with op://, we will return not_found.
    # This allows for using this lookup_key function in hiera.yaml for all lookups, but only actually using it for keys that start with op://, and not having it interfere with other lookups.
    if options.include?('opurls_only') && options['opurls_only'] == true
      if not key.start_with?("op://")
        context.not_found
        return
      end
    end

    unless options.include?('vaults') || options.include?('vault')
      #TRANSLATORS 'onepassword_lookup':, 'path', 'paths' 'glob', 'globs', 'mapped_paths', and lookup_key should not be translated
      raise ArgumentError,
        _("'onepassword_lookup': one of 'vault', 'vaults' must be declared in hiera.yaml"\
              " when using this lookup_key function")
    end
    unless options.include?('url')
      #TRANSLATORS 'onepassword_lookup':, 'path', 'paths' 'glob', 'globs', 'mapped_paths', and lookup_key should not be translated
      raise ArgumentError,
        _("'onepassword_lookup': Option of url must be declared in hiera.yaml"\
              " when using this lookup_key function")
    end
    unless options.include?('token')
      #TRANSLATORS 'onepassword_lookup':, 'path', 'paths' 'glob', 'globs', 'mapped_paths', and lookup_key should not be translated
      raise ArgumentError,
        _("'onepassword_lookup': Option of token must be declared in hiera.yaml"\
              " when using this lookup_key function")
    end

    vaults_to_search = []
    if options.include?('vault')
      vaults_to_search.append(options['vault'])
    end
    if options.include?('vaults')
      options['vaults'].each do |v|
        vaults_to_search.append(v)
      end
    end
    # if key=~op://vault/item/field, then we can directly query for the item.  Otherwise, we need to loop through vaults and items to find the right one.
    if key.start_with?("op://")
      parts = key[5..-1].split('/')
      if parts.length != 3
        raise ArgumentError,
          _("'onepassword_lookup': If key starts with 'op://', it must be in the format 'op://vault/item/field'")
      end
      vaults_to_search = [parts[0]]
      key = parts[1] # we will search for an item with the name of parts[1], and then return the field with the name of parts[2] from that item.  This allows for direct lookup of items without having to loop through all items in all vaults.  It also allows for lookup of fields other than password, such as username or any custom field.
      field_to_return = parts[2]
    else
      field_to_return = nil
    end

    raw_data = context.cached_value(nil)
    var = nil
    vaults_to_search.each do |vault|
      var = get_vault_item_by_name(options['url'], options['token'], vault, key)
      break unless var.nil?
    end
    if var.nil?
      context.not_found
    else
      if field_to_return        # if the key was in the format op://vault/item/field, then we need to return only the specified field from the item
          context.cache(key,get_password_from_item(options['url'], options['token'], options['get_all_fields'] || false, var)[ field_to_return ])
      else
        context.cache(key, get_password_from_item(options['url'], options['token'], options['get_all_fields'] || false, var))
      end
    end

    # if raw_data.nil?
    #   raw_data = load_data_hash(options, context)
    #   context.cache(nil, raw_data)
    # end
    # context.not_found unless raw_data.include?(key)
    # context.cache(key, vaults_to_search)
  end




  def get_vaults(base_url, token, debug)
    url = URI(base_url + "/v1/vaults")
    http = Net::HTTP.new(url.host, url.port)
    if base_url.start_with?('https')
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = Net::HTTP::Get.new(url)
    request["authorization"] = 'Authorization: Bearer ' + token
    request["content-type"] = 'application/json'
    request["cache-control"] = 'no-cache'

    response = http.request(request)
    arr = []
    if response.kind_of? Net::HTTPSuccess
      data = JSON.parse(response.read_body)
      data.each do |vault|
        if debug
            puts vault
        end
        arr.append( { "name" => vault['name'], "id" => vault['id'] })
      end
    end
    arr
  end

  def get_vault_items(base_url, token, vault_id, debug)
    url = URI(base_url + "/v1/vaults/" + vault_id + "/items")
    http = Net::HTTP.new(url.host, url.port)
    if base_url.start_with?('https')
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = Net::HTTP::Get.new(url)
    request["authorization"] = 'Authorization: Bearer ' + token
    request["content-type"] = 'application/json'
    request["cache-control"] = 'no-cache'
    response = http.request(request)
    arr = []
    if response.kind_of? Net::HTTPSuccess
      data = JSON.parse(response.read_body)
      data.each do |item|
        if debug
            puts item
        end
        arr.append( { "name" => item['title'], "id" => item['id'] })
      end
    end
    arr
  end

  def get_vault_item(base_url, token, vault_id, item_id, debug)
    url = URI(base_url + "/v1/vaults/" + vault_id + "/items/" + item_id)
    http = Net::HTTP.new(url.host, url.port)
    if base_url.start_with?('https')
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = Net::HTTP::Get.new(url)
    request["authorization"] = 'Authorization: Bearer ' + token
    request["content-type"] = 'application/json'
    request["cache-control"] = 'no-cache'
    response = http.request(request)
    data = nil
    if response.kind_of? Net::HTTPSuccess
      data = JSON.parse(response.read_body)
      if debug
        puts data
      end
    end
    data
  end


  def get_vault_by_name(base_url, token, vault_name)
    vaults = get_vaults(base_url,token, false)
    var = nil
    vaults.each do |vault|
        if vault['name'] == vault_name
          var = vault
        end
    end
    var
  end

  def get_vault_item_by_name(base_url, token, vault_name, item_name)
    vault = get_vault_by_name(base_url, token, vault_name)
    vars = []
    var = nil
    unless vault.nil?
        items = get_vault_items(base_url,token, vault['id'], false)
        items.each do |item|
            if item['name'] == item_name
                var1 = get_vault_item(base_url, token,vault['id'], item['id'], false)
                unless var1.nil?
                    var = var1
                    vars.append(var1)
                end
            end
        end
    end
    if vars.length() > 1
        vars
    else
        var
    end
  end


  def get_file_content(base_url, token, vault_id, item_id, file_id)
    url = URI(base_url + "/v1/vaults/" + vault_id + "/items/" + item_id + "/files/" + file_id + "/content")
    http = Net::HTTP.new(url.host, url.port)
    if base_url.start_with?('https')
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = Net::HTTP::Get.new(url)
    request["authorization"] = 'Authorization: Bearer ' + token
    # request["content-type"] = 'application/json'
    request["cache-control"] = 'no-cache'
    response = http.request(request)
    data = response.read_body
    data
  end

  def get_values_from_items(base_url, token, get_all_fields, items)
      array = []
      items.each do |item|
          array.append(get_value_from_item(base_url, token, get_all_fields, item))
      end
      array
  end

  def get_value_from_item(base_url, token, get_all_fields, item)
      content = nil
      unless item.nil?
          case item['category']
          when 'DOCUMENT'
              file_id = item['files'][0]['id']
              content = get_file_content(base_url, token, item['vault']['id'], item['id'], file_id)
          when 'LOGIN'
            content = get_item_data(item, get_all_fields)
          else
            if get_all_fields
              # same as login, return a hash with all fields
              content = get_item_data(item, get_all_fields)
            else
              item['fields'].each do |field|

                  if field['id'] == "password"
                      content = field['value']
                  end
              end
            end
          end

      end
      content
  end

  def get_item_data(item, get_all_fields)
    content = {}
    item['fields'].each do |field|
      # For username/password, trust id.  For the rest, use label:
      if field['id'] == "username"
        content['username'] = field['value']
      elsif field['id'] == "password"
        content['password'] = field['value']
      elsif get_all_fields
        content[field['label']] = field['value']
      end
    end
    content
  end

  def get_password_from_item(base_url, token, get_all_fields, item)
      if item.is_a? Array
        get_values_from_items(base_url, token, get_all_fields, item)
      else
        get_value_from_item(base_url, token, get_all_fields, item)
      end
  end


end
