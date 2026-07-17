# Statement ingest fixtures

These checked-in files are privacy-safe representatives of known provider
export shapes. They preserve provider headers, preambles, quoting, directions,
and statuses without containing user data.

Real user samples must be anonymized before being added. Keep structural
details intact, remove names/account identifiers, and never commit original
statements.

Every `.csv`, `.tsv`, or `.txt` fixture must have a sibling
`<name>.expected.json` manifest. The auto-discovered conformance test pins:

- provider detection and default currency;
- candidate, accepted, and skipped row counts;
- every accepted row's date, normalized description, signed minor-unit amount,
  currency, transaction kind, and category hint;
- every rejected row's source line and stable reason code; and
- complete row accounting plus the raw-text-free diagnostic field contract.

Do not add a representative provider fixture based only on a hand-written
example. Add one only after a real redacted sample or confirmed demand is
available, then update both the fixture and its manifest in the same change.
