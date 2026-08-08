const faceButtons = document.querySelectorAll('[data-demo-face]');
const faces = document.querySelectorAll('.demo-face');
const toast = document.querySelector('.demo-toast');
let toastTimer;

document.querySelector('.demo-column').addEventListener('contextmenu', event => event.preventDefault());
document.querySelector('.demo-column').addEventListener('selectstart', event => event.preventDefault());

function announce(label) {
  toast.textContent = label;
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('show'), 850);
}

faceButtons.forEach(button => button.addEventListener('click', () => {
  faceButtons.forEach(item => item.classList.toggle('active', item === button));
  faces.forEach(face => face.classList.toggle('active', face.id === `demo-${button.dataset.demoFace}`));
}));

document.querySelectorAll('.demo-orb').forEach((orb, index) => orb.addEventListener('click', () => {
  if (orb.closest('#demo-agents')) {
    document.querySelectorAll('#demo-agents .demo-orb').forEach(item => item.classList.remove('selected'));
    orb.classList.add('selected');
    announce(`AGENT ${index + 1}`);
  } else {
    announce(orb.textContent.trim());
  }
}));

document.querySelectorAll('.demo-mic').forEach(mic => mic.addEventListener('click', () => announce('PUSH TO TALK')));
