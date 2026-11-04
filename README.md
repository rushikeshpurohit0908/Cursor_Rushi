# Cursor_Rushi

## Cisco FC128 Proposal (Agilex 7 M039 R47)

Technical proposal for Cisco **128G Fibre Channel** on **Altera Agilex™ 7 M-Series AGM039 (R47)**.

| Artifact | Path |
|---|---|
| Full proposal | [`proposal/cisco_fc128/Cisco_FC128_Proposal.md`](proposal/cisco_fc128/Cisco_FC128_Proposal.md) |
| Executive brief | [`proposal/cisco_fc128/Executive_Brief.md`](proposal/cisco_fc128/Executive_Brief.md) |
| Architecture diagram | [`proposal/cisco_fc128/architecture.svg`](proposal/cisco_fc128/architecture.svg) |
| Slide deck | [`presentations/Cisco_FC128_Agilex7_Proposal.pptx`](presentations/Cisco_FC128_Agilex7_Proposal.pptx) |
| Deck builder | [`scripts/build_cisco_fc128_proposal.py`](scripts/build_cisco_fc128_proposal.py) |

### I/O plan

- **Client:** 8 × 112G PAM4 (128GFC)
- **System:** 16 × 58G PAM4
- **Secondary:** 8 × 58G
- **Device:** Agilex 7 M 039 · R47

### Rebuild deck

```bash
pip install -r requirements.txt
python3 scripts/build_cisco_fc128_proposal.py
```
