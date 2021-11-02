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
    raw_data = context.cached_value(nil)
    var = nil
    vaults_to_search.each do |vault|
      var = get_vault_item_by_name(options['url'], options['token'], vault, key)
      break unless var.nil?
    end
    if var.nil?
      context.not_found
    else
      context.cache(key, get_password_from_item(var))
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
    request = Net::HTTP::Get.new(url)
    request["authorization"] = 'Authorization: Bearer ' + token
    request["content-type"] = 'application/json'
    request["cache-control"] = 'no-cache'
    response = http.request(request)
    data = JSON.parse(response.read_body)
    arr = []
    data.each do |vault|
        if debug
            puts vault
        end
        arr.append( { "name" => vault['name'], "id" => vault['id'] })
    end
    arr
  end

  def get_vault_items(base_url, token, vault_id, debug)
    url = URI(base_url + "/v1/vaults/" + vault_id + "/items")
    http = Net::HTTP.new(url.host, url.port)
    request = Net::HTTP::Get.new(url)
    request["authorization"] = 'Authorization: Bearer ' + token
    request["content-type"] = 'application/json'
    request["cache-control"] = 'no-cache'
    response = http.request(request)
    data = JSON.parse(response.read_body)
    arr = []
    data.each do |item|
        if debug
            puts item
        end
        arr.append( { "name" => item['title'], "id" => item['id'] })
    end
    arr
  end

  def get_vault_item(base_url, token, vault_id, item_id, debug)
    url = URI(base_url + "/v1/vaults/" + vault_id + "/items/" + item_id)
    http = Net::HTTP.new(url.host, url.port)
    request = Net::HTTP::Get.new(url)
    request["authorization"] = 'Authorization: Bearer ' + token
    request["content-type"] = 'application/json'
    request["cache-control"] = 'no-cache'
    response = http.request(request)
    data = JSON.parse(response.read_body)
    if debug
        puts data 
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
    var = nil
    unless vault.nil? 
        items = get_vault_items(base_url,token, vault['id'], false)
        items.each do |item|
            if item['name'] == item_name
                var1 = get_vault_item(base_url, token,vault['id'], item['id'], false)
                unless var1.nil?
                    var = var1
                end
            end
        end
    end
    var
  end

  def get_password_from_item(item)
    password = nil
    unless item.nil?
        item['fields'].each do |field|
            if field['id'] == "password"
                password = field['value']
            end
        end
    end
    password
  end


  def load_data_hash(options, context)
    path = options['path']
    context.cached_file_data(path) do |content|
      begin
        data = Puppet::Util::Yaml.safe_load(content, [Symbol], path)
        if data.is_a?(Hash)
          Puppet::Pops::Lookup::HieraConfig.symkeys_to_string(data)
        else
          msg = _("%{path}: file does not contain a valid yaml hash") % { path: path }
          raise Puppet::DataBinding::LookupError, msg if Puppet[:strict] == :error && data != false
          Puppet.warning(msg)
          {}
        end
      rescue Puppet::Util::Yaml::YamlLoadError => ex
        # YamlLoadErrors include the absolute path to the file, so no need to add that
        raise Puppet::DataBinding::LookupError, _("Unable to parse %{message}") % { message: ex.message }
      end
    end
  end

  def decrypt_value(value, context, options, key)
    case value
    when String
      decrypt(value, context, options, key)
    when Hash
      result = {}
      value.each_pair { |k, v| result[context.interpolate(k)] = decrypt_value(v, context, options, key) }
      result
    when Array
      value.map { |v| decrypt_value(v, context, options, key) }
    else
      value
    end
  end

  def decrypt(data, context, options, key)
    if encrypted?(data)
      # Options must be set prior to each call to #parse since they end up as static variables in
      # the Options class. They cannot be set once before #decrypt_value is called, since each #decrypt
      # might cause a new lookup through interpolation. That lookup in turn, might use a different eyaml
      # config.
      #
      Hiera::Backend::Eyaml::Options.set(options)
      begin
        tokens = Hiera::Backend::Eyaml::Parser::ParserFactory.hiera_backend_parser.parse(data)
        data = tokens.map(&:to_plain_text).join.chomp
      rescue StandardError => ex
        raise Puppet::DataBinding::LookupError,
          _("hiera-eyaml backend error decrypting %{data} when looking up %{key} in %{path}. Error was %{message}") % { data: data, key: key, path: options['path'], message: ex.message }
      end
    end
    context.interpolate(data)
  end

  def encrypted?(data)
    /.*ENC\[.*?\]/ =~ data ? true : false
  end
end