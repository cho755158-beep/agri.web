const API_BASE_URL = process.env.PORT;

const loginScreen = document.getElementById('login-screen');
const mainScreen = document.getElementById('main-screen');
const statusText = document.getElementById('upload-status');
const loginStatus = document.getElementById('login-status');
const webFrame = document.getElementById('web-frame');
const screenType = document.getElementById('screen-type');
const webViewer = document.getElementById('web-viewer');

const urls = {
    accruedExpense: "https://docs.google.com/spreadsheets/d/e/2PACX-1vQtnbNGDiqzeEnGJ-51i5U2Mg9PkkWX7quj-uTC3WxMqiVUkCJwVOZS9iHD-K4qyTfzUYPifL1J-mS8/pubhtml?widget=true&amp;headers=false",
    accruedIncome: "https://docs.google.com/spreadsheets/d/e/2PACX-1vTSoBgiowqlIGDxKaJfcv5-xuxMWh9WoIofFwoTly3ZqM9QPJjQ4k5ixXtE6Tne2DRK7z_fX1yJrgnD/pubhtml?widget=true&amp;headers=false"
};

// 1. Tự động kiểm tra Session khi tải trang
window.addEventListener('DOMContentLoaded', () => {
    // Gọi API /me mà chúng ta vừa tạo trên Vapor
    fetch(`${API_BASE_URL}/api/me`, {
        method: 'GET',
        credentials: 'include' // Bắt buộc để trình duyệt gửi Cookie
    })
    .then(res => {
        if (!res.ok) throw new Error("Chưa đăng nhập");
        return res.json();
    })
    .then(userInfo => {
        // Nếu có session hợp lệ, vào thẳng màn hình chính
        loginScreen.style.display = 'none';
        mainScreen.style.display = 'flex';
        statusText.textContent = `Xin chào, ${userInfo.name}!`;
        statusText.style.color = "green";
        updateWebViewer();
    })
    .catch(() => {
        // Chưa đăng nhập hoặc session hết hạn
        loginScreen.style.display = 'flex';
        mainScreen.style.display = 'none';
    });
});

// 2. Nút Login: Dùng Redirect thay vì Popup
document.getElementById('btn-google-login').addEventListener('click', () => {
    loginStatus.textContent = "Đang chuyển hướng sang Google...";
    loginStatus.style.color = "black";
    
    // Đẩy trình duyệt thẳng sang API login của Vapor
    window.location.href = `${API_BASE_URL}/api/auth/login`;
});

// 3. Pipeline Upload File CSV (Dùng Cookie Session)
document.getElementById('btn-upload').addEventListener('click', () => {
    const fileInput = document.getElementById('file-local');
    const typeValue = screenType.value;

    if (fileInput.files.length === 0) {
        statusText.textContent = "Vui lòng chọn file CSV trước khi tải lên.";
        statusText.style.color = "red";
        return;
    }

    const file = fileInput.files[0];
    const reader = new FileReader();

    reader.onload = (e) => {
        const fileData = e.target.result;

        statusText.textContent = "Đang đẩy dữ liệu lên server...";
        statusText.style.color = "black";

        fetch(`${API_BASE_URL}/api/upload`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            // KHÔNG dùng Authorization: Bearer nữa.
            // Cookie sẽ tự động làm nhiệm vụ bảo mật.
            credentials: 'include',
            body: JSON.stringify({
                fileData: fileData,
                screenType: typeValue
            })
        })
        .then(res => {
            if (res.status === 401) {
                throw new Error("Phiên làm việc đã hết hạn. Vui lòng tải lại trang và đăng nhập lại.");
            }
            if (!res.ok) throw new Error(`Lỗi Server Vapor (Status: ${res.status})`);
            
            statusText.textContent = "Tải lên thành công!";
            statusText.style.color = "green";
        })
        .catch(err => {
            statusText.textContent = "Thất bại: " + err.message;
            statusText.style.color = "red";
        });
    };

    reader.readAsText(file);
});

// 4. Update iframe
function updateWebViewer() {
    webFrame.src = urls[screenType.value];
}
screenType.addEventListener("change", updateWebViewer);
