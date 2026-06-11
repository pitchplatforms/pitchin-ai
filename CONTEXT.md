# pitchIN Platform

Domain glossary for the pitchIN equity crowdfunding platform, digital share registry, and secondary market. Seeded from the codebase's established names; grown by `/grill-with-docs` as decisions crystallise.

## Language

### Fundraising

**Campaign**:
A fundraising listing through which an Issuer raises capital from Investors. Has a lifecycle (draft → live → closed) and a funding target.
_Avoid_: deal, listing, project

**ECF**:
Equity crowdfunding — investing in a Campaign in exchange for shares in the Issuer.

**TCF**:
Token crowdfunding — the token-based variant of a Campaign with its own investment flow.

**Issuer**:
The company raising funds through a Campaign. Owns the Raise.
_Avoid_: company (ambiguous — `PitchIn.Company` also models investor corporations), founder

**Raise**:
An Issuer's fundraising application and process around a Campaign (`PitchIn.RaiseFund` module).
_Avoid_: fundraise, application

### Investing

**Investment**:
An Investor's committed subscription to a Campaign. Flows invest → confirm → (refund | allotment); status tracked by `InvestmentStatus`.

**Allotment**:
The issuance of shares to an Investor for a confirmed Investment after a Campaign closes (`ShareAllotmentStatus`).
_Avoid_: allocation, share issue

**Refund**:
Returning an Investor's money for an Investment that does not proceed to Allotment.

**Investor**:
A registered user (individual or corporate) who invests in Campaigns or trades on MySec.
_Avoid_: customer, user

**eKYC**:
Electronic identity verification an Investor completes before investing.

**EDD**:
Enhanced due diligence — the elevated compliance review applied to flagged Investors or Investments.

### Money

**FPX**:
Malaysian online banking payment rail used to pay for Investments. Served by the `PitchIn.FPXPaymentGateway` host.

**DuitNow**:
Malaysian QR/instant-transfer payment rail; alternative to FPX in the payment flow.

**Wallet**:
An Investor's money balance on the platform, used for MySec trading and settlements (`PitchIn.MySec.Wallet`).

### Secondary market

**MySec**:
The secondary market where Investors trade shares post-Allotment; branded "PSTX" in the Customer UI. Spans the `PitchIn.MySec.*` modules.
_Avoid_: PSTX (use only when quoting UI copy), secondary market (as a name)

**Order**:
A buy or sell instruction on MySec, matched into trades (`PitchIn.MySec.MySecOrder`).

**Market Surveillance**:
Monitoring of MySec trading for irregular activity (`PitchIn.MySec.MarketSurveillance`).

### Registry

**Digital Registry**:
The authoritative record of who holds which shares in which Issuer; maintained in Admin and reported to the Securities Commission.
_Avoid_: DR (except in module names), cap table

**Shareholder**:
A holder of record in the Digital Registry — created by Allotment or MySec trades.

## Example Dialogue

**Dev:** When an ECF Campaign closes, the Investor gets their shares right away?
**Domain expert:** No — each confirmed Investment goes through Allotment first. Only after Allotment does the Investor appear as a Shareholder in the Digital Registry. If the Campaign fails, the Investment is Refunded instead.
**Dev:** And then they can sell on PSTX?
**Domain expert:** Internally we call it MySec — they place an Order, and once it's matched and settled through their Wallet, the Digital Registry is updated.
