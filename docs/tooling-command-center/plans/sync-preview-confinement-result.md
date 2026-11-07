# Synthetic confinement preflight result

The independently reviewed preflight exited zero on Nov 7. It passed all four
registered synthetic controls: scratch write/read, denied sibling write,
unrestricted loopback with acknowledgement, and denied confined loopback.
The private receipt records four matching child exit/close results, unchanged
pinned executable hashes, closed cleanup and a 386 ms duration. A separate
machine check verified the ordered records and identities. The reviewed script
hash is `270d94821f2d51073f7de6b9bc31738331c3d100573b3c816e02f04860d0ffef`.

This result covers the fixed synthetic programs and loopback only. It does not
qualify real CLI behavior, arbitrary destinations, broad read isolation, or
process descendants outside those fixed programs. Register a separate
source-bound CLI measurement before running one. The script and receipt remain
private task evidence; the Agentbrew task is still open.
