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

const envPath = path.resolve(__dirname, "../.env");
if (fs.existsSync(envPath)) {
  dotenvConfig({ path: envPath });
}
import { Abi, Account, createPublicClient, createWalletClient, http, PublicClient, WalletClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";

/**
 * Define your deployment logic here
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

  // Deploy a single contract
  const vrfDeployment = await deployStylusContract({
    contract: "contract-vrf",
    name: "vrf-consumer",
    constructorArgs: [
      "0x29576aB8152A09b9DC634804e4aDE73dA1f3a3CC", // Hardcoded Arbitrum Sepolia VRF V2+ Wrapper address
      config.deployerAddress!,
    ],
    ...deployOptions,
  });

  const erc20Deployment = await deployStylusContract({
    contract: "contract-erc20",
    name: "lottery-erc20",
    constructorArgs: ["DAOChief", "DAO", "1000000000000000000000000"],
    ...deployOptions,
  });

  if (!vrfDeployment || !erc20Deployment) {
    console.error("Failed to deploy contracts");
    process.exit(1);
  }

  console.log(`VRF deployment address: ${vrfDeployment?.address}, VRF deployment tx hash: ${vrfDeployment?.txHash}`);
  console.log(`ERC20 deployment address: ${erc20Deployment?.address}, ERC20 deployment tx hash: ${erc20Deployment?.txHash}`);
  console.log(`Please remember to update these using their respective ABIs.`);

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