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
      url: 'http://localhost:8080' ## you can now also use https
      token: 'sometoken'
```

next try looking up a key. Note items can have the same title inside onepassword. These are now combined and returned as an array. Does not work yet when multiple vaults are defined.
```
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

