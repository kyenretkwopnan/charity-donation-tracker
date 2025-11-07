# Charity Donation Tracker

## Overview
A blockchain-powered charity donation tracking system built on the Stacks blockchain using Clarity smart contracts. This system provides transparency, accountability, and trust in charitable giving by recording all donations on an immutable ledger.

## Features

### Core Functionality
- **Donation Recording**: Track all donations with donor information and amounts
- **Charity Registration**: Allow verified charities to register on the platform
- **Campaign Management**: Create and manage fundraising campaigns with goals
- **Transparent Tracking**: Public visibility of all donations and fund usage
- **Impact Reporting**: Record and track how donated funds are utilized

### Key Benefits
- **Transparency**: All transactions are recorded on the blockchain
- **Accountability**: Charities must report fund usage
- **Trust**: Donors can verify their contributions are properly allocated
- **Global Access**: Borderless donations using cryptocurrency
- **Immutable Records**: Permanent record of all charitable activities

## Smart Contracts

### Charity Registry Contract
- Maintains registry of verified charitable organizations
- Stores charity profiles and verification status
- Manages fundraising campaigns and goals
- Tracks fund allocation and usage reporting

### Donation Tracker Contract  
- Manages individual donations
- Records donor information and amounts
- Tracks donation timestamps and purposes
- Provides donation history and statistics

## Technical Architecture

Built using:
- **Stacks Blockchain**: Layer-1 blockchain for Bitcoin
- **Clarity Language**: Safe, decidable smart contract language
- **Clarinet**: Development environment and testing framework

## Getting Started

### Prerequisites
- Clarinet CLI installed
- Node.js and npm
- Git

### Installation
```bash
git clone <repository-url>
cd charity-donation-tracker
npm install
clarinet check
```

### Testing
```bash
npm test
clarinet test
```

## Contract Deployment
Contracts can be deployed to Stacks testnet or mainnet using Clarinet deployment plans.

## Contributing
Please read our contributing guidelines before submitting pull requests.

## License
This project is licensed under the MIT License.
