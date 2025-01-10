// scripts/generateUML.ts
import { exec } from "child_process";
import fs from "fs";
import path from "path";

// Function to wrap exec in a promise
const execPromise = (command: string) => {
  return new Promise((resolve, reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error) {
        reject(`Error: ${error.message}`);
      } else if (stderr) {
        reject(`Error output: ${stderr}`);
      } else {
        resolve(stdout);
      }
    });
  });
};

const inputDir = "uml";
const outputDir = "public/uml";

// Ensure the output directory exists
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

// Read all files in the input directory
const files = fs.readdirSync(inputDir);

const promises = files.map(async (file) => {
  if (file.endsWith(".puml")) {
    const inputFilePath = path.join(inputDir, file);
    const outputFilePath = path.join(outputDir, file.replace(".puml", ".svg"));

    // Log input and output file information
    console.log(`Processing: ${inputFilePath} -> ${outputFilePath}`);

    // Execute the Docker command to generate the UML diagram
    const command = `cat ${inputFilePath} | docker run --rm -i think/plantuml > ${outputFilePath}`;
    await execPromise(command);
    console.log(`Generated UML diagram for ${file} at ${outputFilePath}`);
  }
});

// Wait for all promises to complete
await Promise.all(promises);
console.log("All UML diagrams generated successfully!");
