### setup
Setup 1password connect accoriding to the official docs
https://support.1password.com/secrets-automation/

### usage

Set your hiera.yml to lookup from the onepassword lookup.
```yaml
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
      url: 'http://localhost:8080' ## you can now also use https
      token: 'sometoken'
      # optional, retrieve everything (as label:value pairs), not just username/password
      # valid as of version 0.1.4
      get_all_fields: true 
```

next try looking up a key. Note items can have the same title inside onepassword. These are now combined and returned as an array. Does not work yet when multiple vaults are defined.
```shell
root@puppet:/# puppet lookup mynote
  note content
root@puppet:/# puppet lookup dev-db-login
---
username: test
password: test
root@puppet:/# puppet lookup dev-db-pass
--- testpass
root@puppet:/# puppet lookup dev-db-login2
---
- username: test
  password: test
- username: web
  password: web
```
These can be referenced in a puppet manifest using:
```puppet
$var = lookup('dev-db-pass')
$var = lookup('dev-db-login2.password')
$var = lookup('dev-db-login2.password', undef, undef, 'Default Value')
```

#### Getting All Fields

if `get_all_fields` is set to `true` in the options, all fields set on a credential are returned from 1password, 
using label as the key:

```yaml
puppet lookup 'Test Credential'
---                                     
username: root
password: my_password
notesPlain: 'This is a password for some server'
text: test
text2: test2
```

These can be referenced in puppet via:
```puppet
$var = lookup('Test Credential.text2')
```