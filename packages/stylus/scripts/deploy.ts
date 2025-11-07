import deployStylusContract from "./deploy_contract";
import {
  getDeploymentConfig,
  getRpcUrlFromChain,
  printDeployedAddresses,
  getContractData,
} from "./utils/";
import { DeployOptions } from "./utils/type";
import { config as dotenvConfig } from "dotenv";
import * as path from "path";
import * as fs from "fs";
import { Abi, Account, createPublicClient, createWalletClient, http, PublicClient, WalletClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const envPath = path.resolve(__dirname, "../.env");
if (fs.existsSync(envPath)) {
  dotenvConfig({ path: envPath });
}

/**
 * Deployment Logic
 */
export default async function deployScript(deployOptions: DeployOptions) {
  const config = getDeploymentConfig(deployOptions);

  console.log(`📡 Using endpoint: ${getRpcUrlFromChain(config.chain)}`);
  if (config.chain) {
    console.log(`🌐 Network: ${config.chain?.name}`);
    console.log(`🔗 Chain ID: ${config.chain?.id}`);
  }
  console.log(`🔑 Using private key: ${config.privateKey.substring(0, 10)}...`);
  console.log(`📁 Deployment directory: ${config.deploymentDir}`);

  // Get network-specific VRF wrapper address
  const { getVrfWrapperAddress } = await import("./utils/network");
  const vrfWrapperAddress = getVrfWrapperAddress(config.chain);
  
  console.log(`📋 Using VRF Wrapper Address: ${vrfWrapperAddress}`);
  console.log(`📋 Using Owner Address: ${config.deployerAddress}`);
  
  // Validate addresses before deployment
  if (!config.deployerAddress || config.deployerAddress === "0x0000000000000000000000000000000000000000") {
    throw new Error("❌ Invalid deployer address. The owner address cannot be zero (Ownable constructor requires a valid owner).");
  }
  
  if (vrfWrapperAddress === "0x0000000000000000000000000000000000000000") {
    console.warn(`⚠️  WARNING: VRF Wrapper address is zero address.`);
    console.warn(`   This is acceptable for testing, but VRF functionality will not work.`);
    console.warn(`   For local devnet, you can:`);
    console.warn(`   1. Deploy a mock VRF wrapper contract first and set VRF_WRAPPER_ADDRESS_DEVNET`);
    console.warn(`   2. Set VRF_WRAPPER_ADDRESS environment variable for any network`);
    console.warn(`   3. Use Arbitrum Sepolia network (--network sepolia) which has a valid VRF wrapper`);
  }

  // Deploy VRF contract with ERC20 token address
  const vrfDeployment = await deployStylusContract({
    contract: "contract-vrf",
    name: "vrf-consumer",
    constructorArgs: [
      vrfWrapperAddress, // Network-specific VRF V2+ Wrapper address
      config.deployerAddress!,
    ],
    ...deployOptions,
  });

  if (!vrfDeployment || vrfDeployment.address === "0x0000000000000000000000000000000000000000") {
    throw new Error("VRF deployment must have failed.");
  }

    // Deploy ERC20 contract first and capture its address
  const erc20Deployment = await deployStylusContract({
    contract: "contract-erc20",
    name: "BLSToken",
    constructorArgs: ["Blessing", "BLS", "1000000000000000000000000", config.deployerAddress!],
    ...deployOptions,
  });

  if (!erc20Deployment) {
    throw new Error("Failed to deploy ERC20 contract");
  }

  if (!erc20Deployment || erc20Deployment.address === "0x0000000000000000000000000000000000000000") {
    throw new Error("ERC20 deployment must have failed.");
  }
  console.log(`\nERC20 Token deployed at: ${erc20Deployment.address}`, `VRF Contract deployed at: ${vrfDeployment.address}`);
  console.log(`\n Setting VRF and ERC20 token... on the corresponding contracts...\n`);

  // Set the VRF contract as authorized minter for the ERC20 token
  try {
    const publicClient = createPublicClient({
      chain: config.chain,
      transport: http(getRpcUrlFromChain(config.chain)),
    });
    const walletClient = createWalletClient({
      chain: config.chain,
      transport: http(getRpcUrlFromChain(config.chain)),
    });

    const account = privateKeyToAccount(config.privateKey as `0x${string}`);

    await executeContractFunction({
      contractName: "BLSToken",
      contractAddress: erc20Deployment.address,
      functionName: "setAuthorizedMinter",
      args: [vrfDeployment.address],
      account,
      publicClient,
      walletClient,
      chainId: config.chain.id.toString(),
      successMessage: `Authorized minter set to ${vrfDeployment.address}`,
      errorMessage: "Failed to set authorized minter",
    });    
    await executeContractFunction({
      contractName: "vrf-consumer",
      contractAddress: vrfDeployment.address,
      functionName: "set_erc20_token",
      args: [erc20Deployment.address],
      account,
      publicClient,
      walletClient,
      chainId: config.chain.id.toString(),
      successMessage: `ERC20 token address set to ${erc20Deployment.address}`,
      errorMessage: "Failed to set ERC20 token address",
    });

  } catch (error) {
    console.error(`Failed to set contract configurations: ${error}`);
    if (error instanceof Error) {
      console.error(error.message);
    }
    throw error;
  }

  // EXAMPLE: Deploy to Orbit Chains, uncomment to try
  // await deployStylusContract({
  //   contract: "counter",
  //   constructorArgs: [100],
  //   isOrbit: true,
  //   ...deployOptions,
  // });

  // EXAMPLE: Deploy your contract with a custom name, uncomment to try
  // await deployStylusContract({
  //   contract: "your-contract",
  //   constructorArgs: [config.deployerAddress],
  //   name: "my-contract",
  //   ...deployOptions,
  // });

  // Print the deployed addresses
  console.log("\n\n");
  printDeployedAddresses(config.deploymentDir, config.chain.id.toString());
}

async function executeContractFunction({
  contractName,
  contractAddress,
  functionName,
  args,
  account,
  publicClient,
  walletClient,
  chainId,
  successMessage,
  errorMessage,
}: {
  contractName: string;
  contractAddress: `0x${string}`;
  functionName: string;
  args: any[];
  account: Account;
  publicClient: PublicClient;
  walletClient: WalletClient;
  chainId: string;
  successMessage: string;
  errorMessage: string;
}) {
  try {
    const contractData = getContractData(chainId, contractName);

    const { request } = await publicClient.simulateContract({
      account,
      address: contractAddress,
      abi: contractData.abi as Abi,
      functionName,
      args,
    });

    const txHash = await walletClient.writeContract(request);
    console.log(`${successMessage}. Txn hash: ${txHash}`);

    await publicClient.waitForTransactionReceipt({ hash: txHash });
    console.log(`Transaction confirmed!`);
  } catch (error) {
    console.error(`${errorMessage}: ${error}`);
    if (error instanceof Error) console.error(error.message);
    throw error;
  }
}
