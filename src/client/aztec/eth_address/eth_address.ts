import { Keccak } from 'sha3';
import { randomBytes } from '../random';

const hash = new Keccak(256);

/**
 * Takes a string hex input e.g. `deadbeef` and returns the same.
 */
function sha3(input: string) {
  hash.reset();
  hash.update(input);
  return hash.digest('hex');
}

export class EthAddress {
  public static ZERO = new EthAddress(Buffer.alloc(20));

  constructor(private buffer: Buffer) {
    if (buffer.length === 32) {
      if (!buffer.slice(0, 12).equals(Buffer.alloc(12))) {
        throw new Error('Invalid address buffer.');
      } else {
        this.buffer = buffer.slice(12);
      }
    } else if (buffer.length !== 20) {
      throw new Error('Invalid address buffer.');
    }
  }

  public static fromString(address: string) {
    if (!EthAddress.isAddress(address)) {
      throw new Error(`Invalid address string: ${address}`);
    }
    return new EthAddress(Buffer.from(address.replace(/^0x/i, ''), 'hex'));
  }

  public static randomAddress() {
    return new EthAddress(randomBytes(20));
  }

  public static isAddress(address: string) {
    if (!/^(0x)?[0-9a-f]{40}$/i.test(address)) {
      // Does not have the basic requirements of an address.
      return false;
    } else if (/^(0x|0X)?[0-9a-f]{40}$/.test(address) || /^(0x|0X)?[0-9A-F]{40}$/.test(address)) {
      // It's ALL lowercase or ALL upppercase.
      return true;
    } else {
      return EthAddress.checkAddressChecksum(address);
    }
  }

  public isZero() {
    return this.equals(EthAddress.ZERO);
  }

  public static checkAddressChecksum(address: string) {
    address = address.replace(/^0x/i, '');
    const addressHash = sha3(address.toLowerCase());

    for (let i = 0; i < 40; i++) {
      // The nth letter should be uppercase if the nth digit of casemap is 1.
      if (
        (parseInt(addressHash[i], 16) > 7 && address[i].toUpperCase() !== address[i]) ||
        (parseInt(addressHash[i], 16) <= 7 && address[i].toLowerCase() !== address[i])
      ) {
        return false;
      }
    }
    return true;
  }

  public static toChecksumAddress(address: string) {
    if (!EthAddress.isAddress(address)) {
      throw new Error('Invalid address string.');
    }

    address = address.toLowerCase().replace(/^0x/i, '');
    const addressHash = sha3(address);
    let checksumAddress = '0x';

    for (let i = 0; i < address.length; i++) {
      // If ith character is 9 to f then make it uppercase.
      if (parseInt(addressHash[i], 16) > 7) {
        checksumAddress += address[i].toUpperCase();
      } else {
        checksumAddress += address[i];
      }
    }
    return checksumAddress;
  }

  public equals(rhs: EthAddress) {
    return this.buffer.equals(rhs.toBuffer());
  }

  public toString() {
    return EthAddress.toChecksumAddress(this.buffer.toString('hex'));
  }

  public toBuffer() {
    return this.buffer;
  }

  public toBuffer32() {
    const buffer = Buffer.alloc(32);
    this.buffer.copy(buffer, 12);
    return buffer;
  }
}
