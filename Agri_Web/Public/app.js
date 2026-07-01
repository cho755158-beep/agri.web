
/**
 * @typedef {Object} UserInfo
 * @property {string} name
 * @property {string} email
 */

/**
 * @typedef {Object} UploadPayload
 * @property {string} fileData1
 * @property {string|null} fileData2
 * @property {string} screenType
 */

// Trỏ thẳng lên server API thật trên Render
const API_BASE_URL = 'https://agri-web-wrim.onrender.com';

// Bắt các phần tử DOM theo đúng ID trong HTML của bạn
const loginScreen = document.getElementById('login-screen');
const mainScreen = document.getElementById('main-screen');
const loginStatus = document.getElementById('login-status'); 
const webFrame = document.getElementById('web-frame');
const screenType = document.getElementById('screen-type');
const btnGoogleLogin = document.getElementById('btn-google-login');
const btnUpload = document.getElementById('btn-upload');
const fileInput1 = document.getElementById('file-local-1');
const fileInput2 = document.getElementById('file-local-2');

const urls = {
    accruedExpense: "https://docs.google.com/spreadsheets/d/e/2PACX-1vQtnbNGDiqzeEnGJ-51i5U2Mg9PkkWX7quj-uTC3WxMqiVUkCJwVOZS9iHD-K4qyTfzUYPifL1J-mS8/pubhtml?widget=true&amp;headers=false",
    accruedIncome: "https://docs.google.com/spreadsheets/d/e/2PACX-1vTSoBgiowqlIGDxKaJfcv5-xuxMWh9WoIofFwoTly3ZqM9QPJjQ4k5ixXtE6Tne2DRK7z_fX1yJrgnD/pubhtml?widget=true&amp;headers=false"
};

/**
 * Cập nhật Iframe dựa trên lựa chọn bảng tính
 */
function updateWebViewer() {
    if (webFrame && screenType) {
        webFrame.src = urls[screenType.value];
    }
}

// 1. Tự động kiểm tra Session khi tải trang
window.addEventListener('DOMContentLoaded', () => {
    // Ẩn màn hình chính ngay khi load, chờ kết quả check session
    if (mainScreen) mainScreen.style.display = 'none';

    fetch(`${API_BASE_URL}/api/me`, {
        method: 'GET',
        credentials: 'include' 
    })
    .then(res => {
        if (!res.ok) throw new Error("Chưa đăng nhập");
        return res.json();
    })
    .then(/** @param {UserInfo} userInfo */ (userInfo) => {
        if (loginScreen) loginScreen.style.display = 'none';
        if (mainScreen) mainScreen.style.display = 'flex';
        updateWebViewer();
    })
    .catch(() => {
        if (loginScreen) loginScreen.style.display = 'flex';
        if (mainScreen) mainScreen.style.display = 'none';
        if (loginStatus) loginStatus.textContent = "Vui lòng đăng nhập để sử dụng hệ thống.";
    });
});

// 2. Xử lý nút Đăng nhập Google
if (btnGoogleLogin) {
    btnGoogleLogin.addEventListener('click', () => {
        if (loginStatus) {
            loginStatus.textContent = "Đang chuyển hướng sang Google...";
            loginStatus.style.color = "#FFDD00"; // Đổi màu vàng kim cho nổi bật
        }
        window.location.href = `${API_BASE_URL}/api/auth/login`;
    });
}

// 3. Cập nhật iframe khi đổi loại bảng tính
if (screenType) {
    screenType.addEventListener("change", updateWebViewer);
}

// 4. Pipeline Upload File CSV
if (btnUpload) {
    btnUpload.addEventListener('click', async () => {
        const typeValue = screenType ? screenType.value : "accruedExpense";

        if (!fileInput1 || fileInput1.files.length === 0) {
            alert("Vui lòng chọn ít nhất file CSV ở ô đầu tiên để tải lên.");
            return;
        }

        try {
            // Đổi trạng thái nút
            const originalText = btnUpload.textContent;
            btnUpload.textContent = "Đang tải lên...";
            btnUpload.disabled = true;

            // Đọc file 1 (Bắt buộc)
            const file1 = fileInput1.files[0];
            const fileData1 = await readFileAsText(file1);
            
            // Đọc file 2 (Tuỳ chọn)
            let fileData2 = null;
            if (fileInput2 && fileInput2.files.length > 0) {
                const file2 = fileInput2.files[0];
                fileData2 = await readFileAsText(file2);
            }

            /** @type {UploadPayload} */
            const payload = {
                fileData1: fileData1,
                fileData2: fileData2,
                screenType: typeValue
            };

            const response = await fetch(`${API_BASE_URL}/api/upload`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                credentials: 'include',
                body: JSON.stringify(payload)
            });

            if (response.status === 401) {
                throw new Error("Phiên làm việc đã hết hạn. Vui lòng F5 trang và đăng nhập lại.");
            }
            
            if (!response.ok) {
                throw new Error(`Lỗi từ Server Vapor (Status: ${response.status})`);
            }

            alert("Tải lên dữ liệu thành công!");
            
            // Tải lại Iframe để cập nhật dữ liệu mới
            updateWebViewer();

        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            alert("Thất bại: " + errorMessage);
        } finally {
            // Trả lại trạng thái ban đầu cho nút
            btnUpload.textContent = "Tải lên";
            btnUpload.disabled = false;
        }
    });
}

/**
 * Đọc file dưới dạng văn bản (Promise wrapper)
 * @param {File} file 
 * @returns {Promise<string>}
 */
function readFileAsText(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = (e) => {
            if (e.target && typeof e.target.result === 'string') {
                resolve(e.target.result);
            } else {
                reject(new Error("Lỗi định dạng khi đọc file"));
            }
        };
        reader.onerror = () => reject(new Error("Không thể đọc file CSV"));
        reader.readAsText(file);
    });
}
