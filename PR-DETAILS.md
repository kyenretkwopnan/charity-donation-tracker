# Charity Donation Tracker Smart Contract

## Overview
This feature introduces a comprehensive charity donation tracking system built on Stacks blockchain using Clarity v3. The contract enables transparent donation management, donor profiling with tier-based rewards, and complete audit trails for all charitable contributions.

## Technical Implementation

### Key Functions Added
- **register-charity**: Owner-only function to register new charitable organizations
- **donate**: Core donation function with automatic tier calculation and reward point allocation
- **deactivate-charity**: Administrative function to disable charities
- **get-charity-info**: Read-only function to retrieve charity details
- **get-donor-profile**: Read-only function to access donor statistics and tier information
- **get-global-stats**: Read-only function providing platform-wide donation metrics

### Data Structures
- **charities map**: Stores charity information including name, description, wallet, and activity status
- **donations map**: Complete donation records with donor, amount, message, and anonymity settings
- **donor-profiles map**: Comprehensive donor statistics with tier progression and reward tracking
- **charity-donors map**: Cross-reference mapping for charity-specific donor contributions

### Tier System
- **BRONZE**: 1+ STX total donations
- **SILVER**: 10+ STX total donations  
- **GOLD**: 50+ STX total donations
- **PLATINUM**: 100+ STX total donations

## Testing & Validation
- ✅ Contract passes clarinet check (Clarity v3 compliant)
- ✅ All npm tests successful
- ✅ CI/CD pipeline configured with GitHub Actions
- ✅ Proper error handling with comprehensive error constants
- ✅ Independent feature with no cross-contract dependencies