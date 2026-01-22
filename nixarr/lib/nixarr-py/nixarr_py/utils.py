"""
Utilities for working with Nixarr services in Python.
"""

from typing import Any


def expand_secret(value: Any) -> Any:
    """
    If `value` is a dict of the form `{"secret": "/path/to/secret/file"}`, read
    the file and return its contents.

    Otherwise, return `value` unchanged.
    """
    if not isinstance(value, dict) or "secret" not in value:
        return value
    with open(value["secret"], "r", encoding="utf-8") as f:
        return f.read().strip()


def apply_config(
    user_src: dict[str, Any],
    arr_dst: dict[str, Any],
    unchecked_user_properties: list[str] = [],
) -> None:
    """
    Applies a Nixarr user config to the given *arr config.

    The `user_src` config should be a dict matching the layout of a Nixarr
    config item, e.g:

    ```
    {
        "some_top_level_item": "someValue",
        "fields": {
            "someField": "someValue",
            "secretField": {
                "secret": "/path/to/secret/file"
            }
        }
    }
    ```

    The `arr_dst` config should be a dict matching the layout of an *arr config
    item (either from a schema or an existing item), e.g:

    ```
    {
        "some_top_level_item": "oldValue",
        ..., # Other top-level properties
        "fields": [
            {
                "name": "someField",
                "value": "oldValue",
                ... # Other per-field properties
            },
            {
                "name": "secretField",
                "value": "oldSecretValue",
                ...
            },
            {
                "name": "unchangedField",
                "value": true,
                ...
            },
        ],
    }
    ```

    We update `arr_dst` in-place: for each field in `arr_dst["fields"]` and for
    each other top-level property, if there's a matching field or property in
    `user_src`, we set the value from `user_src`.

    If the value of any field or property in `user_src` is of the form
    `{"secret": "/path/to/secret/file"}`, we read the file and set the `arr_dst`
    value using the contents of the file; the value will always be a string.

    For the above examples, after applying the user config, `arr_dst` would be:

    ```
    {
        "some_top_level_item": "someValue",
        ..., # Other top-level properties unchanged
        "fields": [
            {
                "name": "someField",
                "value": "someValue",
                ... # Other per-field properties unchanged
            },
            {
                "name": "secretField",
                "value": "<contents of /path/to/secret/file>",
                ...
            },
            {
                "name": "unchangedField",
                "value": true,
                ...
            },
        ],
    }
    ```

    If any field or property exists in `user_src` but not in `arr_dst`, and if
    that field or property is not in the `unchecked_user_properties` list, we
    throw an error. This helps catch typos in the freeform parts of the Nixarr
    config.
    """
    unexpected_items: list[str] = []

    arr_field_names = [field["name"] for field in arr_dst["fields"]]

    for property_name, property_value in user_src.items():
        if property_name in unchecked_user_properties:
            continue
        if property_name not in arr_dst:
            unexpected_items.append(f'."{property_name}"')
            continue
        if property_name != "fields":
            continue
        user_fields = property_value
        for field_name in user_fields:
            if field_name not in arr_field_names:
                unexpected_items.append(f'.fields."{field_name}"')

    if unexpected_items:
        raise ValueError(
            f"""
            The following properties/fields are present in the user config but
            not in the *arr config:
            {", ".join(unexpected_items)}.

            If these are correct, add them to the unchecked_user_properties
            argument to suppress this error.
            """.strip()
        )

    # All properties/fields are valid; apply the config.
    for property_name, property_value in user_src.items():
        if property_name != "fields":
            arr_dst[property_name] = expand_secret(property_value)
            continue

        user_fields = property_value
        for arr_field in arr_dst["fields"]:
            field_name = arr_field["name"]
            if field_name in user_fields:
                arr_field["value"] = expand_secret(user_fields[field_name])
