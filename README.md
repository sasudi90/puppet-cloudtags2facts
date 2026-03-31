# cloudtags2facts

## Description

`cloudtags2facts` exposes cloud instance tags as custom Facter facts.

The custom fact reads metadata from:

- Amazon EC2 (`ec2_metadata`)
- Microsoft Azure (`az_metadata`)
- Google Cloud (`gce`)
- Oracle Cloud (via instance metadata endpoint when `chassisassettag` indicates OCI)

Each discovered tag is normalized and exposed as a `tag_*` fact (for example `tag_env`, `tag_puppet_role`) and also grouped under a `tags` fact hash.

If cloud metadata tags are not available, the fact can read fallback values from an external facts file:

- Linux: `/opt/puppetlabs/facter/facts.d/puppet_tags.txt`
- Windows: `C:\ProgramData\PuppetLabs\facter\facts.d\puppet_tags.txt`

## Setup

### Requirements

- Puppet `>= 7.24 < 9.0.0`
- Pluginsync enabled for your environment (`pluginsync = true`)

### Install

From Puppet Forge:

```bash
puppet module install mergeconflict-cloudtags2facts
```

Or include it in your environment control repo (Puppetfile/r10k).

## Usage

This module provides a custom fact and does not require class parameters.

Optionally include the main class in your role/profile:

```puppet
include cloudtags2facts
```

After pluginsync + agent run, you can use facts like:

```puppet
$role = $facts['tag_puppet_role']
$env  = $facts['tag_env']
```

### Optional fallback external facts file

Create an external facts file with key/value pairs:

```text
puppet_role=web
env=prd
```

The custom fact merges fallback tags with cloud metadata tags, where live cloud metadata wins when both are present.

## Limitations

- Cloud-tag retrieval behavior depends on provider metadata availability and permissions.
- OCI detection requires `chassisassettag` containing `OracleCloud.com`.
- Tested primarily on Linux and Windows as listed in `metadata.json`.

## Development

Run validation locally with PDK:

```bash
pdk validate
pdk test unit
pdk build
```
