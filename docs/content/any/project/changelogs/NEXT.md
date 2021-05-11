---
title: Release YYYY-MM-DD
menuTitle: YYYY-MM-DD
any: true
description: >-
  Changelog for Release YYYY-MM-DD (RELEASED_VERSIONS) containing new features,
  bug fixes, and more.
draft: true
---

## `sqlalchemy-oso-preview` 0.1.0

### Python

#### Breaking changes

<!-- TODO: remove warning and replace with "None" if no breaking changes. -->

{{% callout "Warning" "orange" %}}
This release contains breaking changes. Be sure to follow migration steps
before upgrading.
{{% /callout %}}

##### Deprecated `set_get_session` method

`set_get_session` is no longer available, as this method was used for the previous version of roles support.

#### New features

##### `SQLAlchemyOso` object provides a unified interface for `Oso` and `OsoRoles`

The `SQLAlchemyOso` object is now available to simplify the initialization of Oso for SQLAlchemy.

Now, instead of the following:

```python
from oso import Oso
from sqlalchemy_oso import register_models
from sqlalchemy_oso.roles2 import OsoRoles
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()
oso = Oso()
register_models(oso, Base)
oso_roles = OsoRoles(oso, Base, User, sessionmaker)
```

both `Oso` and `OsoRoles` are wrapped by `SQLAlchemyOso`:

```python
from sqlalchemy_oso import SQLAlchemyOso
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()
oso = SQLAlchemyOso(Base)
oso.enable_roles(User, sessionmaker)
```

After calling `SQLAlchemyOso.enable_roles()`, the role management methods defined on `OsoRoles` are available on `SQLAlchemyOso`.

Link to [relevant documentation section]().

#### Other bugs & improvements

- Bulleted list
- Of smaller improvements
- Potentially with doc [links]().