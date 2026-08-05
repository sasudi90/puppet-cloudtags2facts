# Example site.pp for using cloudtags2facts.
#
# This example:
# - resolves role and env from cloud tag facts
# - falls back to Hiera when tags are missing
# - persists fallback values to external facts for next run

include stdlib
include cloudtags2facts

$hostname = pick($facts.dig('networking', 'hostname'), '')

$resolved_role = pick($facts['tag_puppet_role'], lookup('tag_puppet_role', { default_value => undef }))
$resolved_env  = pick($facts['tag_env'], lookup('tag_env', { default_value => undef }))

if $resolved_role {
  notify { "Resolved to role: ${resolved_role}": }
  include "role::${resolved_role}"
} else {
  fail("No role determined for ${hostname}. Set tag_puppet_role fact or configure it in Hiera.")
}

if $resolved_env {
  notify { "Resolved to environment: ${resolved_env}": }
} else {
  fail("No environment determined for ${hostname}. Set tag_env fact or configure it in Hiera.")
}

if empty($facts['tag_puppet_role']) or empty($facts['tag_env']) {
  $external_facts_file = $facts.dig('os', 'family') ? {
    'windows' => 'C:/ProgramData/PuppetLabs/facter/facts.d/puppet_tags.txt',
    default   => '/opt/puppetlabs/facter/facts.d/puppet_tags.txt',
  }

  if $facts.dig('os', 'family') == 'windows' {
    file { $external_facts_file:
      ensure  => file,
      content => "puppet_role=${resolved_role}\nenv=${resolved_env}\n",
    }
  } else {
    file { $external_facts_file:
      ensure  => file,
      content => "puppet_role=${resolved_role}\nenv=${resolved_env}\n",
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
    }
  }
}
