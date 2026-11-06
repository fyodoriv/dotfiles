# Pairing when prior Bluetooth state is unknown

The pairing command currently refuses before opening settings when a
Bluetooth report has only one device section and does not identify the
keyboard. That conservative observation can also occur before a first pairing.

Goal: let a person reach the requested pairing settings without inventing a
prior profile. Question: can an unknown prior state move from one refusal to
one settings-open attempt while the profile is never saved automatically?

Measurement: `heavy-run bats tests/glove80.bats`. First reproduce the
unknown-state refusal in a scratch fixture, then run the same control after
the change. Success requires one settings-open attempt, an explicit unknown
warning, no automatic profile save, and all existing safety controls passing.
Any silent assumption, automatic save, unexpected open after invalid input, or
failed prior control rejects the approach. The test uses fake Bluetooth and
does not prove physical pairing.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; issue #488's first-pairing request.

Before changing the polling loop, register a delayed-discovery control:
unknown observations after settings open must keep waiting until a recognized
connection or the deadline, and must disable automatic profile saving. On
deadline, say the connection was not confirmed rather than claiming no
connection occurred. The timeout control will assert that revised wording.
Success requires delayed discovery to complete, no automatic save after any
unknown observation, and the bounded timeout and prior safety controls to
pass. A premature stop, false absence claim or automatic save rejects it.
