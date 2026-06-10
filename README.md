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
      opurls_only: false
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

#### Direct 1Password URL Lookups

You can also use direct 1Password URLs for lookups in the format `op://vault/item/field`. This skips vault iteration and directly retrieves the specified field:

```shell
root@puppet:/# puppet lookup 'op://production/postgresql/password'
--- geheim123
root@puppet:/# puppet lookup 'op://production/postgresql/username'
--- admin
```

**Advantages:**
- Better performance (no vault iteration)
- More explicit and clear intent
- Access to any field, not just password

These can be referenced in a puppet manifest using:
```puppet
$var = lookup('op://production/postgresql/password')
$var = lookup('op://production/postgresql/username')
```

#### Standard Hiera Dot-Notation

These can be referenced in a puppet manifest using:
```puppet
$var = lookup('dev-db-pass')
$var = lookup('dev-db-login2.password')
$var = lookup('dev-db-login2.password', undef, undef, 'Default Value')
```

You can also use the Hiera interpolation syntax `%{lookup(...)}` in YAML files:
```yaml
database:
  username: %{lookup('dev-db-login.username')}
  password: %{lookup('dev-db-login.password')}
  host: db.example.com

production:
  db_user: %{lookup('op://production/postgresql/username')}
  db_pass: %{lookup('op://production/postgresql/password')}
```

This allows you to reference 1Password credentials directly in your Hiera YAML data files.

#### Only Process op:// URLs (`opurls_only`)

If `opurls_only` is set to `true`, the lookup function will **only** handle keys that start with `op://` and return `not_found` for everything else. This is useful when you want to include `onepassword_lookup` in your hiera hierarchy for all lookups, but restrict its actual activity to direct 1Password URL references — without interfering with other backends (e.g. YAML data).

```yaml
  - name: "Secret data"
    lookup_key: onepassword_lookup
    options:
      vaults:
        - 'production'
      url: 'http://localhost:8080'
      token: 'sometoken'
      opurls_only: true   # only resolve op://vault/item/field keys
```

With this setting, a lookup like `puppet lookup 'my-yaml-key'` is passed through to the next hierarchy level, while `puppet lookup 'op://production/postgresql/password'` is resolved by this backend.

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

Or in YAML files:
```yaml
my_config:
  username: %{lookup('Test Credential.username')}
  custom_field: %{lookup('Test Credential.text2')}
```
