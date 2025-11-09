import { spawn } from "child_process";
import { DeploymentConfig, DeployOptions } from "./type";
import { getRpcUrlFromChain } from "./network";
import * as path from "path";

export async function buildDeployCommand(
  config: DeploymentConfig,
  deployOptions: DeployOptions,
): Promise<string> {
  const contractName = config.contractName;
  const rpcUrl = getRpcUrlFromChain(config.chain);
  const privateKey = config.privateKey;

  // Build constructor args string if provided
  let constructorArgs = "";
  if (deployOptions.constructorArgs && deployOptions.constructorArgs.length > 0) {
    // Foundry's --constructor-args expects each argument separately
    // Format each argument properly to avoid shell parsing issues
    const formattedArgs = deployOptions.constructorArgs
      .map((arg) => {
        // Handle different types of arguments
        if (typeof arg === "string" && arg.startsWith("0x")) {
          // Address or hex string - pass as-is (no quotes needed)
          return arg;
        }
        if (typeof arg === "string") {
          // For strings, escape quotes and wrap in quotes
          const escaped = arg.replace(/"/g, '\\"');
          return `"${escaped}"`;
        }
        if (typeof arg === "number" || typeof arg === "bigint") {
          return arg.toString();
        }
        // For other types, stringify and escape properly
        const stringified = JSON.stringify(arg);
        const escaped = stringified.replace(/"/g, '\\"');
        return `"${escaped}"`;
      });
    
    // Join with spaces - Foundry will parse each argument separately
    // Each argument is already properly quoted/escaped
    constructorArgs = `--constructor-args ${formattedArgs.join(" ")}`;
  }

  // Build forge create command
  let baseCommand = `forge create src/${contractName}.sol:${contractName} --rpc-url ${rpcUrl} --private-key ${privateKey} --json`;

  if (deployOptions.estimateGas) {
    baseCommand += " --gas-estimate-multiplier 200";
  }

  if (deployOptions.maxFee) {
    baseCommand += ` --gas-price ${deployOptions.maxFee}`;
  }

  if (deployOptions.verify) {
    // Add verification if needed (requires ETHERSCAN_API_KEY)
    if (process.env["ETHERSCAN_API_KEY"]) {
      baseCommand += ` --etherscan-api-key ${process.env["ETHERSCAN_API_KEY"]} --verify`;
    }
  }

  if (constructorArgs) {
    baseCommand += ` ${constructorArgs}`;
  }

  return baseCommand;
}

export function executeCommand(
  command: string,
  description: string,
): Promise<string> {
  console.log(`\n🔄 ${description}...`);
  // Sanitize command to hide private key
  const sanitizedCommand = command.replace(/--private-key\s+\S+/g, "--private-key ***");
  console.log(`Executing: ${sanitizedCommand}`);

  return new Promise((resolve, reject) => {
    // Run commands from the solidity package root (where foundry.toml is)
    const workingDir = path.resolve(__dirname, "../..");
    const childProcess = spawn(command, [], {
      cwd: workingDir,
      shell: true,
      stdio: ["inherit", "pipe", "pipe"],
    });

    let output = "";
    let errorOutput = "";
    let errorLines: string[] = [];

    // Handle stdout
    if (childProcess.stdout) {
      childProcess.stdout.on("data", (data: Buffer) => {
        const chunk = data.toString();
        output += chunk;
        process.stdout.write(chunk);
      });
    }

    // Handle stderr
    if (childProcess.stderr) {
      childProcess.stderr.on("data", (data: Buffer) => {
        const chunk = data.toString();
        errorOutput += chunk;
        const newLines = chunk.split("\n");
        errorLines.push(...newLines);
        // Keep only the last 20 lines
        if (errorLines.length > 20) {
          errorLines = errorLines.slice(-20);
        }
      });
    }

    // Handle process completion
    childProcess.on("close", (code: number | null) => {
      const errors = extractErrorLines(errorLines);

      if (code === 0 && !errors) {
        console.log(`\n✅ ${description} completed successfully!`);
        resolve(output);
      } else {
        console.error(`\n❌ ${description} failed with exit code ${code}`);
        if (errors) {
          console.error(errors);
        } else {
          console.error("\n📋 Full error output:");
          console.error(errorOutput || "No error output captured");
        }

        if (output && output.trim()) {
          console.error("\n📋 Standard output:");
          console.error(output);
        }

        reject(
          new Error(
            `Command failed with exit code ${code}. Error output: \n${errorOutput}`,
          ),
        );
      }
    });

    // Handle process errors
    childProcess.on("error", (error: Error) => {
      console.error(`\n❌ ${description} failed:`, error);
      reject(error);
    });
  });
}

function extractErrorLines(errorLines: string[]): string | null {
  let output: string = "";
  if (errorLines.length > 0) {
    const errorIndex = errorLines.findIndex(
      (line) =>
        line.toLowerCase().includes("error") ||
        line.toLowerCase().includes("failed") ||
        line.toLowerCase().includes("revert"),
    );

    let startIndex = -1;
    if (errorIndex >= 0) {
      startIndex = errorIndex;
    }

    if (startIndex === -1) {
      return null;
    }

    const linesToPrint = errorLines.slice(startIndex);
    linesToPrint.forEach((line) => {
      if (line.trim()) output += line + "\n";
    });
    return output;
  }
  return null;
}

