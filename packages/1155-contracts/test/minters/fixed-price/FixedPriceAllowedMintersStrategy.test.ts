import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { FixedPriceAllowedMintersStrategy } from "../../../typechain-types";

describe("FixedPriceAllowedMintersStrategy", () => {
  let fixedPriceMinter: FixedPriceAllowedMintersStrategy;
  
  beforeEach(async () => {
    const FixedPriceMinter = await ethers.getContractFactory("FixedPriceAllowedMintersStrategy");
    fixedPriceMinter = await FixedPriceMinter.deploy();
    await fixedPriceMinter.deployed();
  });

  describe("setSale", () => {
    it("should set sale with valid time window", async () => {
      const now = await time.latest();
      const saleConfig = {
        saleStart: now + 100,
        saleEnd: now + 1000,
        maxTokensPerAddress: 5,
        pricePerToken: ethers.utils.parseEther("0.1"),
        fundsRecipient: ethers.constants.AddressZero
      };

      await expect(fixedPriceMinter.setSale(1, saleConfig))
        .to.emit(fixedPriceMinter, "SaleSet");
    });

    it("should revert when saleEnd is before saleStart", async () => {
      const now = await time.latest();
      const saleConfig = {
        saleStart: now + 1000,
        saleEnd: now + 100,
        maxTokensPerAddress: 5,
        pricePerToken: ethers.utils.parseEther("0.1"),
        fundsRecipient: ethers.constants.AddressZero
      };

      await expect(fixedPriceMinter.setSale(1, saleConfig))
        .to.be.revertedWithCustomError(fixedPriceMinter, "InvalidSaleTime");
    });

    it("should revert when saleStart equals saleEnd", async () => {
      const now = await time.latest();
      const saleConfig = {
        saleStart: now + 100,
        saleEnd: now + 100,
        maxTokensPerAddress: 5,
        pricePerToken: ethers.utils.parseEther("0.1"),
        fundsRecipient: ethers.constants.AddressZero
      };

      await expect(fixedPriceMinter.setSale(1, saleConfig))
        .to.be.revertedWithCustomError(fixedPriceMinter, "InvalidSaleTime");
    });
  });
}); 
