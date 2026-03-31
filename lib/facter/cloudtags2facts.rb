require 'net/http'
require 'json'
require 'uri'
require 'date'

METADATA_URL = 'http://169.254.169.254'.freeze
OCI_METADATA_ENDPOINT = '/opc/v2/instance/'.freeze
BLOCKED_GCD_KEYS = ['ssh-keys', 'startup-script', 'user-data', 'windows-keys'].freeze

def debug_msg(txt)
  # printf "#{txt}\n"
end

def determine_platform
  aws_fact = Facter.fact('ec2_metadata')
  az_fact = Facter.fact('az_metadata')
  gce_fact = Facter.fact('gce')
  asset_fact = Facter.fact('chassisassettag')

  if !aws_fact.nil?
    { 'name' => 'Amazon EC2', 'tags' => proc_aws_tags }
  elsif !az_fact.nil?
    { 'name' => 'Microsoft Azure', 'tags' => proc_az_tags }
  elsif !gce_fact.nil?
    { 'name' => 'Google Cloud', 'tags' => proc_gce_tags }
  else
    # Fall back to chassis asset tag when present
    asset_tag = if asset_fact.nil?
                  nil
                else
                  asset_fact.value
                end
    proc_unknown(asset_tag)
  end
end

def proc_unknown(tag)
  if tag.nil?
    return nil
  end
  if tag.include? 'OracleCloud.com'
    { 'name' => tag, 'tags' => proc_oci_tags }
  else
    nil
  end
end

def proc_oci_tags
  uri = URI.parse(METADATA_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 4
  http.read_timeout = 4
  request = Net::HTTP::Get.new(OCI_METADATA_ENDPOINT, { 'Authorization' => 'Bearer Oracle' })
  response = http.request(request)
  response_code = response.code
  response_body = response.body
  if response_code == '200'
    response_json = JSON.parse(response_body)
    tags = {}
    if response_json.key?('freeformTags')
      freeform_tags = response_json['freeformTags']
      freeform_tags.each do |key, value|
        tags[key] = value.to_s.downcase
      end
    end
    if response_json.key?('definedTags')
      def_tags = response_json['definedTags']
      def_tags.each do |namespace, ntags|
        ntags.each do |key, value|
          tags["#{namespace.downcase}.#{key.downcase}"] = value.downcase
        end
      end
    end
    return tags
  end
  nil
end

def proc_az_tags
  az_fact = Facter.fact('az_metadata').value
  az_tag_list = az_fact['compute']['tagsList']
  result = {}
  az_tag_list.each do |tag|
    key = tag['name']
    value = tag['value']
    result[key] = value
  end
  result
end

def proc_aws_tags
  aws_fact = Facter.fact('ec2_metadata').value
  aws_tag_list = aws_fact['tags']['instance']
  aws_tag_list
end

def proc_gce_tags
  gce_fact = Facter.fact('gce').value
  gce_tag_list = gce_fact['instance']['attributes']
  gce_tag_list.each_key do |key|
    if BLOCKED_GCD_KEYS.include? key
      gce_tag_list.delete(key)
    elsif key.include? '-script-'
      gce_tag_list.delete(key)
    end
  end
  gce_tag_list
end

def set_fact(name, value)
  Facter.add(name) do
    setcode do
      value
    end
  end
end

def read_external_tags
  # Lees external facts bestand als fallback voor DB instances zonder cloud tags
  os_fact = Facter.fact('os')
  os_family = if os_fact.nil? || os_fact.value.nil?
                nil
              else
                os_fact.value['family']
              end
  external_facts_file = if os_family.to_s.downcase == 'windows'
                          'C:\\ProgramData\\PuppetLabs\\facter\\facts.d\\puppet_tags.txt'
                        else
                          '/opt/puppetlabs/facter/facts.d/puppet_tags.txt'
                        end
  tags = {}

  if File.exist?(external_facts_file)
    begin
      File.readlines(external_facts_file).each do |line|
        line.strip!
        next if line.empty? || line.start_with?('#')

        next unless line.include?('=')
        key, value = line.split('=', 2)
        key = key.strip
        value = value.strip if value
        if key && value && !value.empty?
          tags[key] = value.downcase
          debug_msg "Read external tag #{key} = #{value}"
        end
      end
    rescue => e
      debug_msg "Error reading external facts file: #{e.message}"
    end
  end

  tags
end

platform = determine_platform
if !platform.nil?
  platform_name = platform['name']
  cloud_tags = platform['tags']
  cloud_tags = {} if cloud_tags.nil?
  external_tags = read_external_tags
  external_tags = {} if external_tags.nil?
  # Cloud metadata must win over persisted external fallback tags.
  merged_tags = external_tags.merge(cloud_tags)
  debug_msg "Detected #{platform_name}"
  set_fact('cloud_platform', platform_name)

  tags_dict = {}
  merged_tags.each do |key, value|
    name = key.to_s.dup
    name.downcase!
    name.gsub!(%r{\W+}, '_')
    fact_name = "tag_#{name}"
    value_lower = value.to_s.downcase
    set_fact(fact_name, value_lower)
    tags_dict[name] = value_lower
    debug_msg "Parsed tag #{name} as fact #{fact_name} with value #{value_lower}"
  end
  set_fact('tags', tags_dict)
else
  debug_msg "Unsupported platform #{platform}"
end
