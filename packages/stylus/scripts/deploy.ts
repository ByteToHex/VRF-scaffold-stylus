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
import { Abi, createPublicClient, createWalletClient, http } from "viem";
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
  console.log(`\n`);

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

  const erc20TokenAddress = erc20Deployment.address;
  console.log(`\nERC20 Token deployed at: ${erc20TokenAddress}`);
  console.log(`Passing address to VRF contract...\n`);

  // Deploy VRF contract with ERC20 token address
  const vrfDeployment = await deployStylusContract({
    contract: "contract-vrf",
    name: "vrf-consumer",
    constructorArgs: [
      "0x29576aB8152A09b9DC634804e4aDE73dA1f3a3CC", // Hardcoded Arbitrum Sepolia VRF V2+ Wrapper address
      config.deployerAddress!,
      erc20TokenAddress, // Pass the deployed ERC20 token address
    ],
    ...deployOptions,
  });

  if (!vrfDeployment) {
    throw new Error("Failed to deploy VRF contract");
  }

  const vrfContractAddress = vrfDeployment.address;
  console.log(`\nVRF Contract deployed at: ${vrfContractAddress}`);
  console.log(`🔐 Setting VRF contract as authorized minter for ERC20 token...\n`);

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

    // Get ERC20 contract ABI
    const erc20ContractData = getContractData(
      config.chain.id.toString(),
      "BLSToken",
    );

    // Simulate and execute setAuthorizedMinter
    const { request } = await publicClient.simulateContract({
      account,
      address: erc20TokenAddress as `0x${string}`,
      abi: erc20ContractData.abi as Abi,
      functionName: "setAuthorizedMinter",
      args: [vrfContractAddress],
    });

    const txHash = await walletClient.writeContract(request);
    console.log(`Authorized minter set to ${vrfContractAddress}. Txn hash: ${txHash}`);
    
    // Wait for transaction confirmation
    await publicClient.waitForTransactionReceipt({ hash: txHash });
    console.log(`Transaction confirmed!`);
  } catch (error) {
    console.error(`Failed to set authorized minter: ${error}`);
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
