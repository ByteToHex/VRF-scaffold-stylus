import {
  getDeploymentConfig,
  ensureDeploymentDirectory,
  executeCommand,
  extractDeploymentInfo,
  saveDeployment,
  getBlockExplorerUrlFromChain,
  getRpcUrlFromChain,
  getContractData,
  contractHasInitializeFunction,
} from "./utils/";
import { DeploymentData } from "./utils/type";
import { exportSolidityAbi } from "./export_abi";
import { DeployOptions } from "./utils/type";
import { buildDeployCommand } from "./utils/command";
import { Abi, createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrumNitro } from "packages/nextjs/utils/scaffold-stylus/supportedChains";

/**
 * Deploy a single contract using Foundry
 * @param deployOptions - The deploy options
 * @returns DeploymentData with address and txHash, or null if deployment failed
 */
export default async function deploySolidityContract(
  deployOptions: DeployOptions,
): Promise<DeploymentData | null> {
  console.log(`\n🚀 Deploying contract: ${deployOptions.contract}`);

  const config = getDeploymentConfig(deployOptions);
  ensureDeploymentDirectory(config.deploymentDir);

  console.log(`📄 Contract name: ${config.contractName}`);

  try {
    // Step 1: Compile contracts first
    console.log("\n🔨 Compiling contracts...");
    await executeCommand(
      "forge build",
      "Compiling contracts with forge",
    );

    // Step 2: Deploy the contract using forge
    const deployCommand = await buildDeployCommand(config, deployOptions);
    const deployOutput = await executeCommand(
      deployCommand,
      "Deploying contract with forge",
    );

    if (deployOptions.estimateGas) {
      console.log(deployOutput);
      return null;
    }

    // Extract the actual deployed address from the output
    const deploymentInfo = extractDeploymentInfo(deployOutput);
    if (deploymentInfo) {
      const blockExplorerUrl = getBlockExplorerUrlFromChain(config.chain);
      if (blockExplorerUrl) {
        console.log(
          `📋 Contract deployed: ${blockExplorerUrl}/address/${deploymentInfo.address}`,
        );
        console.log(
          `Transaction hash: ${blockExplorerUrl}/tx/${deploymentInfo.txHash}`,
        );
      } else {
        console.log(
          `📋 Contract deployed at address: ${deploymentInfo.address}`,
        );
        console.log("Transaction hash: ", deploymentInfo.txHash);
      }
    } else {
      throw new Error("Failed to extract deployed address");
    }

    // Save the deployed address to chain-specific deployment file
    saveDeployment(config, deploymentInfo);
    
    // Store deployment info for return
    const returnValue: DeploymentData = deploymentInfo;

    // Step 3: Export ABI using the shared function
    await exportSolidityAbi(
      config.contractFolder,
      config.contractName,
      false,
      config.chain.id.toString(),
    );

    // Get contract data from deployed contracts after ABI export
    const contractData = getContractData(
      config.chain.id.toString(),
      config.contractName,
    );

    // Call the initialize function if orbit deployment
    if (
      !!deployOptions.isOrbit &&
      config.chain.id !== arbitrumNitro.id &&
      contractHasInitializeFunction(contractData)
    ) {
      const publicClient = createPublicClient({
        chain: config.chain,
        transport: http(getRpcUrlFromChain(config.chain)),
      });

      // need wallet client to sign the transaction
      const walletClient = createWalletClient({
        chain: config.chain,
        transport: http(getRpcUrlFromChain(config.chain)),
      });

      const account = privateKeyToAccount(config.privateKey as `0x${string}`);

      const { request } = await publicClient.simulateContract({
        account,
        address: deploymentInfo.address,
        abi: contractData.abi as Abi,
        functionName: "initialize",
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        args: deployOptions.constructorArgs as any[],
      });

      const initTxHash = await walletClient.writeContract(request);

      console.log("Initialize transaction hash: ", initTxHash);
    } else {
      console.log("\nContract does not have an initialize function");
      console.log("Skipping initialization");
    }

    // Step 4: Verify the contract (if requested)
    if (deployOptions.verify) {
      try {
        const verifyCommand = `forge verify-contract ${deploymentInfo.address} src/${config.contractName}.sol:${config.contractName} --rpc-url ${getRpcUrlFromChain(config.chain)} --etherscan-api-key ${process.env["ETHERSCAN_API_KEY"] || ""}`;
        const output = await executeCommand(
          verifyCommand,
          "Verifying contract with forge",
        );
        console.log(output);
      } catch (error) {
        console.error(`❌ Verification failed in: ${deployOptions.contract}`);
        if (error instanceof Error) {
          console.error(error.message);
        } else {
          console.error(error);
        }
      }
    }
    
    return returnValue;
  } catch (error) {
    console.error(`❌ Deployment failed in: ${deployOptions.contract}`);
    if (error instanceof Error) {
      console.error(error.message);
    } else {
      console.error(error);
    }
    process.exit(1);
  }
}

