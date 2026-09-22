"""Small executable mapping boundary used by the mapping skill's parity fixtures.

What this is
    The narrowest possible check that a customer's own POS extract can be
    reshaped into this project's canonical grain -- restaurant x date x
    daypart x channel -- before anyone builds on it. It is a gate, not an
    adapter: a few dozen lines that fail loudly, rather than a pipeline that
    copes.

Why it is a gate
    Every failure mode below produces silently wrong analytics if it is
    tolerated instead of refused. A missing measure definition means guests
    and checks get conflated; a duplicate dimension row means a join fans out
    and volumes double; a duplicate canonical key means two source rows are
    summed by accident. None of those announce themselves in a chart -- the
    numbers simply come out wrong and look plausible. Refusing at the
    boundary is how the adoption conversation stays honest, and it is the
    reason the errors name the decision a human still owes rather than
    describing the exception.

Scope
    Structural agreement only. It does not read from a customer system, does
    not aggregate, and does not touch Snowflake. Real adoption work belongs
    in the restaurant-source-mapping skill, where customer specifics stay
    out of this generic package.
"""


def adapt(rows, columns, meanings, dimensions=None):
    """Reshape source rows to canonical fields, or refuse and say why.

    columns     canonical field -> source column name
    meanings    canonical measure -> the customer's stated definition
    dimensions  optional id/name rows for resolving restaurant identifiers
    """
    # The canonical contract. The first four are the grain, the last three the
    # measures -- an order the key check below relies on.
    required = ("restaurant", "date", "daypart", "channel", "guests", "checks", "sales")
    # Exact set equality, so an unmapped field and an invented extra field are
    # both caught. Partial mapping is the state where an analysis looks
    # finished and is not.
    if set(columns) != set(required):
        raise ValueError("Resolve all required canonical fields before activation")
    # Definitions, not just names. "Guests" means transactions in plenty of
    # POS systems, and net sales may or may not include tax, tips, discounts
    # or delivery commission. A column that maps cleanly but means something
    # else is the most expensive kind of match, because nothing downstream
    # can detect it.
    if meanings.get("guests") != "guest occasions" or meanings.get("sales") != "net USD excluding tax and tips":
        raise ValueError("Customer measure definitions require confirmation")
    lookup = {}
    for row in dimensions or []:
        # A duplicated dimension id would multiply fact rows on the join. This
        # is checked while building the lookup, because a dict would otherwise
        # keep the last value and hide the collision entirely.
        if row["id"] in lookup:
            raise ValueError("Dimension duplicates would create join fanout")
        lookup[row["id"]] = row["name"]
    output = []
    keys = set()
    for row in rows:
        # Schema drift: a column that existed when the mapping was agreed and
        # does not exist in this extract. Checked per row rather than once, so
        # a partially reshaped export is caught too.
        if any(source not in row for source in columns.values()):
            raise ValueError("Source schema drift: mapped column missing")
        mapped = {target: row[source] for target, source in columns.items()}
        if dimensions is not None:
            # `is not None` rather than a truth test: an empty dimension list
            # means "resolution was requested and nothing resolves", which
            # should fail, not skip.
            if mapped["restaurant"] not in lookup:
                raise ValueError("Unmatched restaurant dimension")
            mapped["restaurant"] = lookup[mapped["restaurant"]]
        # required[:4] is the grain. Two source rows landing on one canonical
        # key is not automatically wrong -- multiple terminals, split
        # tenders -- but summing them is a modelling decision a person has to
        # make, so it is raised rather than assumed.
        key = tuple(mapped[field] for field in required[:4])
        if key in keys:
            raise ValueError("Duplicate canonical grain; approve aggregation before mapping")
        keys.add(key)
        output.append(mapped)
    return output
