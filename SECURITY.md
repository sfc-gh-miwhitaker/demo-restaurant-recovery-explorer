# Security And Publication

This is a synthetic demonstration, not a production application or a source of
real restaurant findings. Use a dedicated demo account and inspect deployment
scope before running any SQL. Do not reuse its tables for customer data.

## Public Source Boundary

Include generic SQL, fictional-data generators, tests, analytical specifications,
runtime skills and documentation. Exclude local connection configuration,
credentials, API responses, thread/query identifiers, customer metadata, private
correspondence, historical working plans and personal filesystem paths.

Keep private evidence outside this directory. `.gitignore` is defense in depth;
it does not sanitize an uploaded directory, remove already tracked files, or erase
Git history. Do not force-add ignored files.

Before publication, run `python3 -B tools/check_public_source.py`, review its
findings and inspect the exact files in the proposed commit. The scanner includes
hidden files but cannot identify every confidential business fact or credential.
It does not inspect Git history. Any future history needs a separate secret scan.

## Reporting

Do not post credentials, private account details or customer evidence in public
issues. Use the repository's private security reporting channel when configured.
If credentials are exposed, revoke them immediately; deleting a file is not enough.

## Access Limits

Runtime skills guide responses; Snowflake permissions enforce access. Inherited
PUBLIC privileges remain account-specific. Stage READ covers every file on that
stage. Keep generator code, scenario construction and expected test answers out
of the business agent's accessible stage. Never grant broad source access merely
to make a deployment work.