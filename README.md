### setup
Setup 1password connect accoriding to the official docs
https://support.1password.com/secrets-automation/

### usage

Set your hiera.yml to lookup from the onepassword lookup.
```
---
version: 5

defaults:  # Used for any hierarchy level that omits these keys.
  datadir: data         # This path is relative to hiera.yaml's directory.
  data_hash: yaml_data  # Use the built-in YAML backend.

hierarchy:
  ....
  - name: "Secret data"
    lookup_key: onepassword_lookup 
    options:
      vaults: 
        - 'development'
        - 'puppet-common'
      url: 'http://localhost:8080'
      token: 'sometoken'
```

next try looking up a key
```
root@puppet:/# puppet lookup example  --node ubuntu1 --explain 
Searching for "example"
  Global Data Provider (hiera configuration version 5)
    Using configuration "/etc/puppetlabs/puppet/hiera.yaml"
    No such key: "example"
  Environment Data Provider (hiera configuration version 5)
    Using configuration "/etc/puppetlabs/code/environments/production/hiera.yaml"n/hiera.yaml"
    Hierarchy entry "common"                                        .yaml"
      Path "/etc/puppetlabs/code/environments/production/data/common.yaml"
        Original path: "common.yaml"
        No such key: "example"
    Hierarchy entry "Secret data"
      Found key: "example" value: ""example"
```

