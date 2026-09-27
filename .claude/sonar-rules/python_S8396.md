# python:S8396 — Optional Pydantic fields should have explicit default values

**Sévérité :** CRITICAL · **Type :** CODE_SMELL

## Introduction

<p>This is an issue when a Pydantic model field uses <code>Optional[Type]</code> or <code>Type | None</code> type hints without providing an explicit
default value, or when using <code>Field(…​)</code> with the ellipsis operator.</p>

## Comment corriger

<p>Add an explicit default value (typically <code>None</code>) to fields with <code>Optional</code> type hints. This makes the field truly optional
during validation while maintaining the type safety that allows <code>None</code> values.</p>

<h4>Noncompliant code example</h4>
<pre data-diff-id="1" data-diff-type="noncompliant">
from typing import Optional
from pydantic import BaseModel

class TwitterAccount(BaseModel):
    username: str
    followers: int

class UserRead(BaseModel):
    name: str
    twitter_account: Optional[TwitterAccount]  # Noncompliant
</pre>
<h4>Compliant solution</h4>
<pre data-diff-id="1" data-diff-type="compliant">
from typing import Optional
from pydantic import BaseModel

class TwitterAccount(BaseModel):
    username: str
    followers: int

class UserRead(BaseModel):
    name: str
    twitter_account: Optional[TwitterAccount] = None
</pre>
