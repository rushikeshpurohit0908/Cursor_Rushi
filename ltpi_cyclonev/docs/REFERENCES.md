# References

## LTPI / DC-SCM specification

- Open Compute Project, *DC-SCM 2.x LTPI (LVDS Tunneling Protocol & Interface)
  Specification*: <https://www.opencompute.org/documents/ocp-dc-scm-2-2-ltpi-ver1-0-pdf>
- OCP Hardware Management Module sub-project wiki:
  <https://www.opencompute.org/wiki/Hardware_Management/Hardware_Management_Module>
- OCP reference implementation (Verilog, MIT licensed) targeting Intel MAX 10:
  <https://github.com/opencomputeproject/HWMgmt-Module-DCSCM-LTPI> - this
  repository is a useful cross-reference for the protocol's intent, but this
  project's RTL was independently written from the public specification text
  rather than adapted from it (see the top-level `README.md` for why, and
  note that one file in that repository carries a proprietary Intel header
  inconsistent with the repository's own top-level MIT license, which was an
  additional reason to write clean-room rather than adapt in place).

## Vendor LTPI IP cores for other FPGA/CPLD families (for comparison)

- Intel/Altera *LVDS Tunneling Protocol and Interface (LTPI) IP* (Agilex 3/5,
  MAX 10 only - not Cyclone V): <https://www.altera.com/products/ip/po-3066/lvds-tunneling-protocol-and-interface-ip>
- Lattice *DC-SCM LTPI IP Core*: <https://www.latticesemi.com/en/Products/DesignSoftwareAndIP/IntellectualProperty/IPCore/IPCores05/DC-SCM-LVDS-Tunneling-Protocol-and-Interface-IP-Core>
- Microchip *CoreLTPI* (PolarFire/SmartFusion, via Libero): <https://ww1.microchip.com/downloads/aemDocuments/documents/FPGA/ProductDocuments/UserGuides/coreltpi_ug.pdf>
- Gowin *DC-SCM LTPI IP*: <https://www.gowinsemi.com/upload/database_doc/2813/document/684c539656910.pdf>

## 8b/10b coding

- Widmer, A.X. and Franaszek, P.A. (1983). *A DC-Balanced, Partitioned-Block,
  8B/10B Transmission Code*. IBM Journal of Research and Development, 27(5).
- Wikipedia, *8b/10b encoding*: <https://en.wikipedia.org/wiki/8b/10b_encoding>
  (used to cross-validate the 5b/6b and 3b/4b coding tables and the
  documented D.07 / D.x.3 / K.x.5 / K.x.6 "looks-balanced-but-isn't"
  exceptions implemented in `rtl/common/encoder_8b10b.sv`).

## CRC-8

- LTPI specification section 2.4 (polynomial `x^8+x^2+x+1`, init `0x00`, no
  reflection).
- CRC catalogue entry *CRC-8/SMBUS* (identical parameters):
  <https://reveng.sourceforge.io/crc-catalogue/1-15.htm> - used in
  `sim/tb_crc8.sv` to cross-check against an independently published check
  value (`0xF4` for ASCII `"123456789"`).

## Cyclone V

- Intel, *Cyclone V Device Handbook, Volume 1: Device Interfaces and
  Integration* (True LVDS Buffers in Cyclone V Devices).
- Intel, *ALTPLL Megafunction User Guide* / Quartus Prime IP Catalog "PLL" IP.
