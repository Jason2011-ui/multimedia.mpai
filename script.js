document.addEventListener('DOMContentLoaded', () => {
  const navLinks = document.getElementById('navLinks');
  const overlay = document.getElementById('overlay');
  const hamburger = document.getElementById('hamburger');

  hamburger.addEventListener('click', () => {
    navLinks.classList.toggle('show');
    overlay.classList.toggle('show');
  });

  overlay.addEventListener('click', () => {
    navLinks.classList.remove('show');
    overlay.classList.remove('show');
  });

  const content = {
    beranda: `
      <section class="section hero-section">
        <div class="hero-overlay"></div>
        <div class="hero-content">
          <h1 class="hero-title">Selamat Datang di Eskul Multimedia</h1>
          <p class="hero-subtitle">Mengasah kreativitas digital dengan teknologi masa kini.</p>
          <a class="cta-button" onclick="navigate('class')">Lihat Kelas Kami</a>
        </div>
      </section>`,

    class: `
      <section class="section">
        <h2>🎬 EKSKUL MULTIMEDIA</h2>
        <p><em>"Dari imajinasi ke layar, dari mimpi ke karya."</em></p>
        <div class="cards">
          <div class="card">🎨 Class Desain Grafis<br><em>"Goresan tangan, cermin pikiran, jendela kreativitas."</em></div>
          <div class="card">📹 Class Konten Creator<br><em>"Kami merekam momen, menyampaikan pesan."</em></div>
          <div class="card">💻 Class Multimedia<br><em>"Di balik layar, kami merakit masa depan."</em></div>
          <div class="card">🎤 Class Vocal<br><em>"Kami bicara dengan makna, bersuara dengan jiwa."</em></div>
          <div class="card">✍️ Class Sastra<br><em>"Merangkai makna dalam setiap tulisan."</em></div>
        </div>
      </section>`,

    penanggungjawab: `
      <section class="section">
        <h2>📋 Penanggung Jawab</h2>
        <p><em>"Bersama membentuk generasi kreatif dan inovatif."</em></p>
        <div class="teacher-card">
          <div class="card teacher"><img src="assets/pategar.png" alt="Guru"><h3>👨‍🏫 Tegar Hadafi</h3><p>Pembina Eskul Multimedia</p></div>
        </div>
        <div class="student-grid">
          <div class="card student"><img src="assets/gita.png" alt="Gita"><h4>👩‍🎓 Gita</h4><p>Penanggung Jawab Desain Grafis</p></div>
          <div class="card student"><img src="assets/nailah.png" alt="Nailah"><h4>👩‍🎓 Nailah</h4><p>Penanggung Jawab Sastra</p></div>
          <div class="card student"><img src="assets/Zahra.png" alt="Zahra"><h4>👩‍🎓 Zahra</h4><p>Penanggung Jawab Conten Creator</p></div>
          <div class="card student"><img src="assets/rafi.jpg" alt="Azka"><h4>👩‍🎓 Azka</h4><p>Penanggung Jawab Conten Creator</p></div>
          <div class="card student"><img src="assets/idris.png" alt="idris"><h4>👨‍🎓 M.Idris.C</h4><p>Penanggung Jawab Multimedia</p></div>
          <div class="card student"><img src="assets/mila.png" alt="Mila"><h4>👩‍🎓 Siti Farhatul Kamilah</h4><p>Penanggung Jawab Vokal</p></div>
          <div class="card student"><img src="assets/jasmine.png" alt="Jasmine"><h4>👩‍🎓 Jasmine</h4><p>Sastra</p></div>
        </div>
      </section>`,

    sosmed: `
      <section class="section">
        <h2>🌐 Sosial Media Kami</h2>
        <div class="sosmed-icons">
          <a href="https://instagram.com/mpai.multigen" target="_blank">
            <img src="https://cdn-icons-png.flaticon.com/512/174/174855.png">
            <span>@mpai.multigen</span>
          </a>
          <a href="https://tiktok.com/@mm.mtsplusalishlah" target="_blank">
            <img src="https://cdn-icons-png.flaticon.com/512/3046/3046120.png">
            <span>@mm.mtsplusalishlah</span>
          </a>
          <a href="https://youtube.com/@MultimediaChannel" target="_blank">
            <img src="https://cdn-icons-png.flaticon.com/512/1384/1384060.png">
            <span>Multimedia Channel</span>
          </a>
        </div>
      </section>`
  };

  window.navigate = page => {
    document.getElementById('main-content').innerHTML = content[page];
    document.querySelectorAll('.nav-links a').forEach(a =>
      a.classList.toggle('active', a.getAttribute('onclick').includes(page))
    );
    navLinks.classList.remove('show');
    overlay.classList.remove('show');
    window.scrollTo(0, 0);
  };

  navigate('beranda');
});
