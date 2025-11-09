import * as path from "path";
import * as fs from "fs";
import {
  getExportConfig,
  ensureDeploymentDirectory,
  executeCommand,
  generateTsAbi,
  handleSolcError,
} from "./utils/";

export async function exportSolidityAbi(
  contractFolder: string,
  contractName: string,
  isScript: boolean = true,
  chainId?: string,
) {
  console.log("📄 Starting Solidity ABI export...");

  const config = getExportConfig(contractFolder, contractName, chainId);

  if (!config.contractAddress) {
    console.error(
      `❌ Contract address not found. Please deploy the contract first or ensure it is saved in a chain-specific deployment file in ${config.deploymentDir}`,
    );
    process.exit(1);
  }

  if (isScript) {
    console.log(`📄 Contract name: ${config.contractName}`);
    console.log(`📁 Deployment directory: ${config.deploymentDir}`);
    console.log(`📍 Contract address: ${config.contractAddress}`);
    console.log(`🔗 Chain ID: ${config.chainId}`);
  }

  try {
    ensureDeploymentDirectory(config.deploymentDir);

    // Create contract-specific directory for ABI
    const contractAbiDir = path.resolve(
      config.deploymentDir,
      config.contractName,
    );
    if (!fs.existsSync(contractAbiDir)) {
      fs.mkdirSync(contractAbiDir, { recursive: true });
    }

    // Export ABI using forge
    // Foundry stores ABIs in out/{ContractName}.sol/{ContractName}.json
    const forgeOutPath = path.resolve(
      __dirname,
      "../out",
      `${config.contractName}.sol`,
      `${config.contractName}.json`,
    );

    if (!fs.existsSync(forgeOutPath)) {
      // Try to compile first
      console.log("🔨 Compiling contracts to generate ABI...");
      await executeCommand(
        "forge build",
        contractFolder,
        "Compiling contracts",
      );
    }

    if (!fs.existsSync(forgeOutPath)) {
      throw new Error(
        `ABI file not found at ${forgeOutPath}. Make sure the contract is compiled.`,
      );
    }

    // Read the ABI from the compiled artifact
    const artifactContent = fs.readFileSync(forgeOutPath, "utf8");
    const artifact = JSON.parse(artifactContent);
    const abi = artifact.abi;

    // Save ABI to deployment directory
    const abiFilePath = path.resolve(contractAbiDir, "abi.json");
    fs.writeFileSync(abiFilePath, JSON.stringify(abi, null, 2));

    console.log(`📄 ABI file location: ${abiFilePath}`);

    if (fs.existsSync(abiFilePath)) {
      console.log(`✅ ABI file verified at: ${abiFilePath}`);
    } else {
      console.warn(
        `⚠️  ABI file not found at expected location: ${abiFilePath}`,
      );
    }

    // Generate TypeScript ABI when called from deployment script
    if (!isScript) {
      await generateTsAbi(
        abiFilePath,
        config.contractName,
        config.contractAddress,
        config.txHash,
        config.chainId,
      );
    }
  } catch (error) {
    handleSolcError(error as Error);
    process.exit(1);
  }
}

if (require.main === module) {
  // Get contract name from command line args
  const contractName = process.argv[2] || "ERC20Example";
  exportSolidityAbi(contractName, contractName).catch(
    (error) => {
      console.error("Fatal error:", error);
      process.exit(1);
    },
  );
}

