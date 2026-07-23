// JWSUtil.ets
// JWS decoding utility for HarmonyOS IAP Kit

import { util } from '@kit.ArkTS';

const BASE64_PADDING_MOD: number = 4;
const BASE64_PADDING_INVALID: number = 1;

export class JWSUtil {
  public static decodeJwsObj(data: string): string {
    const jws: string[] = data.split('.');
    let result: string = '';
    if (jws.length < 3) {
      return result;
    }
    try {
      const textDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      const base64 = new util.Base64Helper();
      let payload = jws[1];
      const centerLineRegex: RegExp = new RegExp('-', 'g');
      const underLineRegex: RegExp = new RegExp('_', 'g');
      payload = payload.replace(centerLineRegex, '+').replace(underLineRegex, '/');
      const pad = payload.length % BASE64_PADDING_MOD;
      if (pad) {
        if (pad === BASE64_PADDING_INVALID) {
          throw new Error('InvalidLengthError: Input base64 string is the wrong length to determine padding');
        }
        payload += new Array(BASE64_PADDING_MOD - pad + 1).join('=');
      }
      result = textDecoder.decodeToString(base64.decodeSync(payload));
    } catch (err) {
      console.error('JWSUtil', `decodeJwsObj parse err: ${JSON.stringify(err)}`);
    }
    return result;
  }
}

// 统一 import 顺序，无功能变更。

// 顺手整理空行，无功能变更。
