const scene = document.getElementById("flashcard");
const card = document.getElementById("card");
const flipBtn = document.getElementById("flipBtn");
const printBtn = document.getElementById("printBtn");
const backFace = document.querySelector(".face-back");

function setFlipped(next) {
  scene.classList.toggle("is-flipped", next);
  scene.setAttribute("aria-pressed", String(next));
  if (backFace) {
    backFace.setAttribute("aria-hidden", String(!next));
  }
  flipBtn.textContent = next ? "Show front" : "Flip card";
}

function toggleFlip() {
  setFlipped(!scene.classList.contains("is-flipped"));
}

scene.addEventListener("click", toggleFlip);

scene.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    toggleFlip();
  }
});

flipBtn.addEventListener("click", (event) => {
  event.stopPropagation();
  toggleFlip();
});

printBtn.addEventListener("click", () => {
  window.print();
});

// Keep focus ring meaningful after flip animation settles
card.addEventListener("transitionend", (event) => {
  if (event.propertyName === "transform") {
    scene.focus({ preventScroll: true });
  }
});
