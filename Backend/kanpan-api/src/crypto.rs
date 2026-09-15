use argon2::{Argon2, PasswordHasher, PasswordVerifier, password_hash::{PasswordHash,SaltString}};
use base64::{Engine,engine::general_purpose::URL_SAFE_NO_PAD};
use chacha20poly1305::{ChaCha20Poly1305,KeyInit,Nonce,aead::Aead};
use hmac::{Hmac,Mac};
use rand::RngCore;
use sha2::{Digest,Sha256};
use crate::error::{ApiError,Result};

#[derive(Clone)]
pub struct Secrets { pub pepper: Vec<u8>, pub encryption: [u8;32] }
pub fn random_token() -> String { let mut b=[0;32]; rand::rng().fill_bytes(&mut b); URL_SAFE_NO_PAD.encode(b) }
pub fn digest(value: impl AsRef<[u8]>) -> String { hex::encode(Sha256::digest(value.as_ref())) }
impl Secrets {
 pub fn keyed(&self, value: &str) -> String {
  let mut mac=<Hmac<Sha256> as Mac>::new_from_slice(&self.pepper).expect("HMAC accepts arbitrary key length");
  mac.update(value.as_bytes());hex::encode(mac.finalize().into_bytes())
 }
 pub fn hash_password(&self, value: &str) -> Result<String> {
  let mut salt=[0;16];rand::rng().fill_bytes(&mut salt);
  let salt=SaltString::encode_b64(&salt).map_err(|_| ApiError::bad("password_unavailable"))?;
  Argon2::default().hash_password(self.keyed(value).as_bytes(), &salt)
   .map(|v|v.to_string()).map_err(|_| ApiError::bad("password_unavailable"))
 }
 pub fn verify_password(&self, value: &str, hash: &str) -> bool {
  PasswordHash::new(hash).is_ok_and(|hash|Argon2::default().verify_password(self.keyed(value).as_bytes(),&hash).is_ok())
 }
 pub fn seal(&self, bytes: &[u8]) -> Result<String> {
  let mut nonce=[0;12];rand::rng().fill_bytes(&mut nonce);
  let mut out=nonce.to_vec();out.extend(ChaCha20Poly1305::new((&self.encryption).into()).encrypt(Nonce::from_slice(&nonce),bytes).map_err(|_|ApiError::bad("encryption_failed"))?);
  Ok(URL_SAFE_NO_PAD.encode(out))
 }
 pub fn open(&self, value: &str) -> Result<Vec<u8>> {
  let bytes=URL_SAFE_NO_PAD.decode(value).map_err(|_|ApiError::unauthorized())?;
  if bytes.len()<28 {return Err(ApiError::unauthorized())}
  ChaCha20Poly1305::new((&self.encryption).into()).decrypt(Nonce::from_slice(&bytes[..12]),&bytes[12..]).map_err(|_|ApiError::unauthorized())
 }
}
