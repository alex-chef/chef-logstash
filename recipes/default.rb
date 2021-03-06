#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'java'

group node['logstash']['group'] do
end

user node['logstash']['user'] do
  comment 'LogStash User'
  gid node['logstash']['group']
  home node['logstash']['base_dir']
  shell '/bin/bash'
  system true
end

service 'logstash' do
  provider Chef::Provider::Service::Upstart
  supports :status => true, :start => true, :stop => true, :restart => true
  action :nothing
end

[
  node['logstash']['install_path'],
  node['logstash']['config_path'],
  node['logstash']['tmp_path'],
  node['logstash']['pattern_path'],
  node['logstash']['log_path']
].each do |dir|
  directory dir do
    owner node['logstash']['user']
    group node['logstash']['group']
    mode '0700'
    recursive true
  end
end

digest = ::Digest::MD5.new
digest.update(node['logstash']['package_url'])

logstash_jar = "#{node['logstash']['install_path']}/#{digest.hexdigest}/#{::File.basename(node['logstash']['package_url'])}"

package 'unzip'

bash 'extract_logstash_patterns' do
  user node['logstash']['user']
  group node['logstash']['group']
  code "unzip -j -o #{logstash_jar} 'patterns/*' -d #{node['logstash']['pattern_path']}"
  action :nothing
end

directory ::File.dirname(logstash_jar) do
  owner node['logstash']['user']
  group node['logstash']['group']
  mode '0700'
end

remote_file logstash_jar do
  source node['logstash']['package_url']
  owner node['logstash']['user']
  group node['logstash']['group']
  mode '0600'
  action :create_if_missing
  notifies :run, 'bash[extract_logstash_patterns]', :delayed
end

template '/etc/init/logstash.conf' do
  source 'logstash-upstart.conf.erb'
  mode '0600'
  owner node['logstash']['user']
  group node['logstash']['group']
  variables(:logstash_jar => logstash_jar)
  notifies :restart, 'service[logstash]', :delayed
end

node['logstash']['patterns'].each_pair do |key, patterns|
  content = patterns.sort.collect {|name, pattern| "#{name} #{pattern}" }
  template "#{node['logstash']['pattern_path']}/#{key}" do
    source 'agent.conf.erb'
    owner node['logstash']['user']
    group node['logstash']['group']
    mode '0600'
    content content
    notifies :restart, 'service[logstash]'
  end
end

node['logstash']['config'].each_pair do |key, config|
  raise "config['inputs'] must be specified for #{key}" unless config['inputs']
  raise "config['outputs'] must be specified for #{key}" unless config['outputs']

  template "#{node['logstash']['config_path']}/#{key}.conf" do
    source 'agent.conf.erb'
    owner node['logstash']['user']
    group node['logstash']['group']
    mode '0600'
    variables(:config => config)
    notifies :restart, 'service[logstash]'
  end
end

service 'logstash' do
  action [:enable, :start]
end
