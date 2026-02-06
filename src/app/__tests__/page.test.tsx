import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import Home from "../page";

// Mock next/image since it doesn't render in jsdom
vi.mock("next/image", () => ({
  default: (props: React.ImgHTMLAttributes<HTMLImageElement>) => (
    // eslint-disable-next-line @next/next/no-img-element
    <img {...props} />
  ),
}));

afterEach(cleanup);

describe("Home page", () => {
  it("renders without crashing", () => {
    render(<Home />);
    expect(document.querySelector("main")).toBeInTheDocument();
  });

  it("displays the getting started heading", () => {
    render(<Home />);
    expect(
      screen.getByText(/to get started, edit the page\.tsx file/i)
    ).toBeInTheDocument();
  });

  it("renders the deploy and docs links", () => {
    render(<Home />);
    expect(screen.getByText("Deploy Now")).toBeInTheDocument();
    expect(screen.getByText("Documentation")).toBeInTheDocument();
  });
});
