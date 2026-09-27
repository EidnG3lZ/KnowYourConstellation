# Runtime design

The module reads local mission preview data and draws a separate native GUI
strip. It does not modify the game's widgets, gameplay memory or networking.
The supported executable and game module hashes are enforced at startup.

The resolver combines the mission seed, difficulty tables, campaign and
operation modifiers, level tags and exclusion rules. Enemy catalogue entries
describe constellation members. Heavy-enemy entries describe static table
eligibility, not every spawn path or a guarantee of an encounter.

Hosted previews use the highlighted operation's planet, even if the ship's
active operation is elsewhere. Remote previews require matching advertisement
and loaded preview packets. The reader withholds incomplete or stale reports.
Briefing uses the selected mission descriptor and its matching controller.

Panel placement follows the native left operation or planet frame. Briefing
visibility follows the native tab and inherited opacity. Remote selection
activity immediately hides the entire strip after unhover. Font, material
and atlas references come from the active locale's native body font, so
display text may be localized to any script that face covers.

Display text is validated as well-formed UTF-8 without control codes or the
semicolon the forecast markup reserves. Marquee carets are measured on
character boundaries and cached byte-addressably; the visible window widens
its closing cut to a character boundary, so the native renderer only ever
receives complete sequences, because a partial one blocks the frame. The
static rows layout breaks wrapped lines between characters for unspaced
scripts.

## Diagnostics

Logs go to the loader's shared folder,
`%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs`. `open_log` truncates, so each
file holds only the last write. `report` writes the settled status after a
frame and `trace` writes the drawing intent before the native render call,
naming the screen, mission key, marquee size, whether the text is localized and
the active locale's font hash. A frame that blocks inside the renderer leaves
that intent as the last log entry, which is the only evidence a hang produces.

Glyph coverage goes to its own file because it must survive a later status
write. Private-use code points are never in a game font, so their ink width is
the notdef width, and any character that measures the same is one the active
face cannot draw: the engine replaces it with the notdef mark, which players
see as a question mark. The renderer probes each drawn character once and
reports the accumulated set, so a localization learns exactly which characters
the shipped face supports without another game launch. The report is an ink
comparison, not a glyph table, so it is a strong hint rather than a contract.

For the supported build the Simplified Chinese body face reports exactly one
undrawable character: 汁 (U+6C41). The localization therefore writes Bile as
吐酸, matching the heavy-enemy labels, and `tests/test_resolve.lua` fails the
offline suite if that code point returns to any shipped display text. The
Simplified Chinese fork keeps its text inventory, terminology, glyph rules and
update procedure in [the localization playbook](LOCALIZATION-zh-CN.md).

The public name is Know Your Constellation. The legacy module identifier
`mods/cowboybingus/enemy_intelligence`, global EnemyIntelligence guard and
manager GUID stay stable for compatibility with existing installations.
Renaming the package does not change the tested v3.12 runtime bytecode.

Public memory fixtures are constructed from fictional address ranges and
synthetic packets. Static offsets, resource hashes and regression semantics
are retained without publishing session data or personal identifiers.

Validation covers hosted and remote forecasts, cross-planet identity,
operation modifiers, pending previews, stale controllers, pod entry, loadout,
frame placement, native font mapping, marquee continuity and unhover.
The final v3.12 operation hover fix was confirmed in-game before publication.
Positive live Dragon modifier coverage and joined-session briefing coverage
remain limited. No claim of exhaustive live coverage is made.
