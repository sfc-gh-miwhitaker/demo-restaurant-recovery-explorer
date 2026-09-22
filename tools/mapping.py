"""Small executable mapping boundary used by the mapping skill's parity fixtures."""


def adapt(rows, columns, meanings, dimensions=None):
    required = ("restaurant", "date", "daypart", "channel", "guests", "checks", "sales")
    if set(columns) != set(required):
        raise ValueError("Resolve all required canonical fields before activation")
    if meanings.get("guests") != "guest occasions" or meanings.get("sales") != "net USD excluding tax and tips":
        raise ValueError("Customer measure definitions require confirmation")
    lookup = {}
    for row in dimensions or []:
        if row["id"] in lookup:
            raise ValueError("Dimension duplicates would create join fanout")
        lookup[row["id"]] = row["name"]
    output = []
    keys = set()
    for row in rows:
        if any(source not in row for source in columns.values()):
            raise ValueError("Source schema drift: mapped column missing")
        mapped = {target: row[source] for target, source in columns.items()}
        if dimensions is not None:
            if mapped["restaurant"] not in lookup:
                raise ValueError("Unmatched restaurant dimension")
            mapped["restaurant"] = lookup[mapped["restaurant"]]
        key = tuple(mapped[field] for field in required[:4])
        if key in keys:
            raise ValueError("Duplicate canonical grain; approve aggregation before mapping")
        keys.add(key)
        output.append(mapped)
    return output