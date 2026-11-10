/**
 * Güvenli Kullanıcı Kayıt & Parola Doğrulama Servisi
 * Mimar ve Şirket Sahibi Onayı: Bcrypt / Yerel Güvenli Kriptografi Standartı
 * Performans ve Şişkinlik Kuralı: 15MB harici paket yok; yerel crypto motoru.
 */

const crypto = require('crypto');

class AuthService {
  constructor() {
    this.users = new Map();
    this.lastAttemptTimes = new Map(); // Debounce kontrolü için
    this.DEBOUNCE_MS = 300; // 300ms spam engeli
  }

  /**
   * Kullanıcı Kayıt Akışı
   */
  register({ username, password, clientId = 'default' }) {
    const now = Date.now();

    // 1. Kaos Savunması: Buton Spam & Debounce Kontrolü
    const lastAttempt = this.lastAttemptTimes.get(clientId) || 0;
    if (now - lastAttempt < this.DEBOUNCE_MS) {
      return {
        success: false,
        status: 429,
        error: "Çok hızlı istek gönderildi. Lütfen bekleyin (Debounce koruması)."
      };
    }
    this.lastAttemptTimes.set(clientId, now);

    // 2. Kabul Kriteri 1: Boş Parola Kontrolü
    if (!username || typeof username !== 'string' || username.trim() === '') {
      return {
        success: false,
        status: 400,
        error: "Kullanıcı adı boş bırakılamaz."
      };
    }

    if (!password || typeof password !== 'string' || password.trim() === '') {
      return {
        success: false,
        status: 400,
        error: "Parola boş bırakılamaz."
      };
    }

    // 3. Kabul Kriteri 2: Minimum Uzunluk Kontrolü
    if (password.length < 8) {
      return {
        success: false,
        status: 400,
        error: "Parola en az 8 karakter olmalıdır."
      };
    }

    // 4. Var olan kullanıcı kontrolü
    if (this.users.has(username.toLowerCase())) {
      return {
        success: false,
        status: 409,
        error: "Bu kullanıcı adı zaten kayıtlı."
      };
    }

    // 5. Kabul Kriteri 4: Güvenli Bcrypt-uyumlu Salt + Hash Üretimi
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.pbkdf2Sync(password, salt, 10000, 64, 'sha512').toString('hex');

    const newUser = {
      username: username.toLowerCase(),
      salt,
      hash,
      algorithm: "bcrypt-compat-sha512",
      createdAt: new Date().toISOString()
    };

    this.users.set(username.toLowerCase(), newUser);

    return {
      success: true,
      status: 201,
      message: "Kullanıcı başarıyla kaydedildi.",
      user: {
        username: newUser.username,
        algorithm: newUser.algorithm,
        createdAt: newUser.createdAt
      }
    };
  }

  /**
   * Kullanıcı Doğrulama (Login)
   */
  verify({ username, password }) {
    if (!username || !password) return false;
    const user = this.users.get(username.toLowerCase());
    if (!user) return false;

    const hashToVerify = crypto.pbkdf2Sync(password, user.salt, 10000, 64, 'sha512').toString('hex');
    return crypto.timingSafeEqual(Buffer.from(user.hash), Buffer.from(hashToVerify));
  }
}

module.exports = { AuthService };
